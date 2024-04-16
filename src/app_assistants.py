# Import necessary libraries  
import streamlit as st    
import pandas as pd  
import json, dotenv, os, time, pyodbc
from openai import AzureOpenAI

# Load environment variables from .env file
dotenv.load_dotenv(override=True)

# Initialize Azure OpenAI Client
client = AzureOpenAI(azure_endpoint=os.environ['AZURE_OPENAI_API_ENDPOINT'], 
                     api_version=os.environ['AZURE_OPENAI_API_VERSION'], 
                     api_key=os.environ['AZURE_OPENAI_API_KEY'])

######################### UTILITIES START #########################

def connect_to_sql_db():
    """
    Connects to the target SQL database and returns a connection object

    """
    SERVER = os.getenv('SERVER')  
    DATABASE = os.getenv('DATABASE')  
    USERNAME = os.getenv('SQL_USERNAME')  
    PASSWORD = os.getenv('PASSWORD')  
    SQL_DB_CONNECTION_STRING = os.getenv('SQL_DB_CONNECTION_STRING')

    if not SQL_DB_CONNECTION_STRING:
        # Create a connection string for the Azure SQL database  
        conn_str = f'Driver={{ODBC Driver 17 for SQL Server}};Server={SERVER};Database={DATABASE};UID={USERNAME};PWD={PASSWORD}'  
    else:
        conn_str = SQL_DB_CONNECTION_STRING

    # Establish a connection with the database
    conn = pyodbc.connect(conn_str)

    return conn

def get_assistant(client):
    assistant_id = os.getenv('ASSISTANT_ID')
    assistants = client.beta.assistants.list()

    return_value = None

    for assistant in assistants:
        if assistant.name == 'sqlchat':
            return_value = assistant
        elif assistant.id == assistant_id:
            return assistant
            
    if not return_value:
        return_value = create_assistant(client)

    return return_value

def create_assistant(client):
    model = os.getenv('AZURE_OPENAI_CHAT_MODEL_DEPLOYMENT_NAME')

    # read the assistant sys msg from file
    assistant_sys_msg = open('assistant_sys_msg.txt', 'r').read()

    # read the get_sql_db_schema function from file
    get_sql_db_schema_func = json.loads(open('get_sql_db_schema.json', 'r').read())

    # read the query_sql_db function from file
    query_sql_db_func = json.loads(open('query_sql_db.json', 'r').read())

    assistant = client.beta.assistants.create(
        name="sqlchat",
        instructions=assistant_sys_msg,
        tools=[
            {
                "type": "code_interpreter"
            },
            {
                "type": "function",
                "function": get_sql_db_schema_func
            },
            {
                "type": "function",
                "function": query_sql_db_func
            }
        ],
        model=model
    )

    return assistant

def get_sql_db_schema(database):
    """
    Retrieves schema (tables, columns, and column types) for target SQL database and returns as a JSON dictionary

    :param database: str, the name of the SQL database.

    """
    with connect_to_sql_db() as conn:
        # Create a cursor from the connection
        cursor = conn.cursor()

        # Get all tables in the database
        cursor.execute("SELECT table_schema, table_name FROM information_schema.tables WHERE table_type = 'BASE TABLE'")
        tables = cursor.fetchall()

        table_details = []

        # For each table, get all columns and their types
        for table in tables:
            curr_table = {'table': f'{table.table_schema}.{table.table_name}', 'columns': []}
            cursor.execute(f"SELECT column_name, data_type FROM information_schema.columns WHERE table_schema = '{table.table_schema}' AND table_name = '{table.table_name}'")
            columns = cursor.fetchall()
            for column in columns:
                curr_table['columns'].append({'name': column.column_name, 'type': column.data_type})
            table_details.append(curr_table)
        
    return table_details

def query_sql_db(query):
    """
    Executes a query against an Azure SQL database and returns results as a pandas dataframe

    :param query: str, query to be executed.
    """
    with connect_to_sql_db() as conn:
        # Execute the query and return the results as a pandas dataframe
        dataframe = pd.read_sql(query, conn)
        return dataframe

# Define a function that waits for a run to complete  
def wait_on_run(run, thread):  
    # Loop until the run status is neither 'queued' nor 'in_progress'  
    while run.status == "queued" or run.status == "in_progress":  
        # Retrieve the latest status of the run  
        run = client.beta.threads.runs.retrieve(  
            thread_id=thread.id,  
            run_id=run.id,  
        )  
        # Sleep for half a second before checking the status again  
        time.sleep(0.5)  
    # Return the run object once it is no longer queued or in progress  
    return run  
  
# Define a function to submit a message to a thread  
def submit_message(assistant_id, thread, user_message):  
    # Create a message in the thread with the role of 'user'  
    client.beta.threads.messages.create(  
        thread_id=thread.id, role="user", content=user_message  
    )  

    # Create a run associated with the thread and assistant  
    return client.beta.threads.runs.create(  
        thread_id=thread.id,  
        assistant_id=assistant_id,  
    )  
  
# Define a function to get the list of messages from a thread  
def get_response(thread):  
    # List messages in ascending order  
    return client.beta.threads.messages.list(thread_id=thread.id, order="asc")  
  
# Define a function to pretty print messages  
def pretty_print(messages):  
    print("# Messages")  
    # Iterate over the messages and print them with the role and content  
    for m in messages:  
        print(f"{m.role}: {m.content[0].text.value}")  
    print()  
  
# Define a function to create a new thread and submit a message to it  
def create_thread_and_run(user_input, assistant_id):  
    # Create a new thread  
    thread = client.beta.threads.create()  
    # Submit the user's message to the thread  
    run = submit_message(assistant_id, thread, user_input)  
    # Return the thread and run objects  
    return thread, run  
  
# Import json_normalize from pandas to flatten JSON objects  
from pandas import json_normalize  
  
# Define a function to handle a conversation turn  
def start_conversation_turn(run, thread):  
    # Initialize a flag to keep the conversation going  
    keep_going = True  
  
    # Loop while the conversation is active  
    while keep_going:  
        # Wait for the run to complete  
        run = wait_on_run(run, thread)  
  
        # Check if the run requires any action  
        if run.required_action != None:  
            # Extract the first tool call from the required actions  
            tool_calls = run.required_action.submit_tool_outputs.tool_calls[0]  
            # Get the function name of the tool call  
            func_name = tool_calls.function.name  
            # Parse the arguments for the function from JSON  
            args = json.loads(tool_calls.function.arguments)  
  
            # Get the thread response  
            thread_resp = get_response(thread)  
  
            # Parse the assistant's message from the thread response  
            assist_msg = json.loads(thread_resp.json())['data'][-1]['content'][0]['text']['value']  
  
            # Initialize the response variable  
            response = None  
  
            # Check if the required function is to get the SQL database schema  
            if func_name == "get_sql_db_schema":  
                # Display a message indicating that the database schema is being gathered  
                with st.chat_message('assistant'):  
                    st.write('*Gathering Database Schema*')  
  
                try:  
                    # Call the function to get the SQL database schema with the provided arguments  
                    response = (get_sql_db_schema(args['database']))  
                    # Normalize the JSON response to create a dataframe  
                    expanded_df = json_normalize((response), record_path='columns', meta='table')  
                    # Display the dataframe in an expandable section  
                    with st.expander("SQL Database Schema"):  
                        st.dataframe(expanded_df)  
                    # Append the schema to the session state messages  
                    st.session_state.messages.append({'role': 'schema', 'content': expanded_df})  
                    # Convert the response to a string for submission  
                    response = str(response)  
  
                except Exception as e:  
                    # Handle any exceptions and store the error message  
                    response = 'Encountered error: ' + str(e)  
                    # Append the error message to the session state messages  
                    st.session_state.messages.append({'role': 'schemaerror', 'content': response})  
                    # Display the error message in an expandable section  
                    with st.expander("Database Schema"):  
                        st.write(response)  
  
            # Check if the required function is to query the SQL database  
            elif func_name == "query_sql_db":  
                # Display the SQL query in an expandable section  
                with st.expander("SQL Query"):  
                    st.write(f'```{args["query"]}```')  
                    # Append the SQL query to the session state messages  
                    st.session_state.messages.append({'role': 'sqlquery', 'content': args['query']})  
                try:  
                    # Call the function to execute the SQL query with the provided arguments  
                    response = (query_sql_db(args['query']))  
                    # Display the query results in an expandable section  
                    with st.expander("SQL Data"):  
                        st.dataframe(response)  
                    # Append the query results to the session state messages  
                    st.session_state.messages.append({'role': 'sqldata', 'content': response})  
                    # Convert the response to a string for submission  
                    response = str(response)  
                except Exception as e:  
                    # Handle any exceptions and store the error message  
                    response = 'Encountered error: ' + str(e)  
                    # Display the error message in an expandable section  
                    with st.expander("SQL Data"):  
                        st.write(response)  
                    # Append the error message to the session state messages  
                    st.session_state.messages.append({'role': 'sqlerror', 'content': response})  
  
            # Display a message indicating that analysis is in progress  
            with st.chat_message('assistant'):  
                st.write('*Analyzing...*')  
  
            # Submit the tool outputs back to the API to update the run  
            run = client.beta.threads.runs.submit_tool_outputs(  
                thread_id=thread.id,  
                run_id=run.id,  
                tool_outputs=[  
                    {  
                        "tool_call_id": tool_calls.id,  
                        "output": response,  
                    }  
                ]  
            )  
  
        else:  
            # If no required action, set the flag to False to exit the loop  
            keep_going = False  


# Define a function to update messages in the Streamlit session state  
def update_messages():  
    # Iterate over each message in the session state's messages list  
    for message in st.session_state.messages:  
        # Check if the message role is 'image'  
        if message['role'] == 'image':  
            # Create a chat message block with the role 'assistant'  
            with st.chat_message('assistant'):  
                # Display the image content of the message  
                st.image(message['content'])  
  
        # Check if the message role is 'schema'  
        elif message['role'] =='schema':  
            # Create an expandable section titled "Database Schema"  
            with st.expander("Database Schema"):  
                # Display the dataframe content of the message  
                st.dataframe(message['content'])  
  
        # Check if the message role is 'schemaerror'  
        elif message['role'] =='schemaerror':  
            # Create an expandable section titled "Database Schema"  
            with st.expander("Database Schema"):  
                # Write the error content of the message  
                st.write(message['content'])  
  
        # Check if the message role is 'sqlquery'  
        elif message['role'] =='sqlquery':  
            # Create an expandable section titled "SQL Query"  
            with st.expander("SQL Query"):  
                # Write the SQL query content of the message as a code block  
                st.write(f"```{message['content']}")  
  
        # Check if the message role is 'sqldata'  
        elif message['role'] =='sqldata':  
            # Create an expandable section titled "SQL Data"  
            with st.expander("SQL Data"):  
                # Display the dataframe content of the message  
                st.dataframe(message['content'])  
  
        # Check if the message role is 'sqlerror'  
        elif message['role'] =='sqlerror':  
            # Create an expandable section titled "SQL Data"  
            with st.expander("SQL Data"):  
                # Write the error content of the message  
                st.write(message['content'])  
  
        # If the message role is anything else  
        else:  
            # Create a chat message block with the role specified in the message  
            with st.chat_message(message['role']):  
                # Display the content of the message using markdown formatting  
                st.markdown(message['content'])  

######################### UTILITIES END #########################

# Define global variables to track the first message and its state  
global first_message, first_message_set  
first_message = ''  # Variable to store the first message  
first_message_set = False  # Flag to indicate if the first message has been set  
  
# Initialize variables for thread and run to None, these will be used later for conversation management  
thread = None  
run = None  
  
# Set the title of the Streamlit app  
st.title('SQL Chat Demo - Azure OpenAI Assistants API')  
# Provide instructions to the user on how to use the app  
st.write('Ask a spoken-word question of your SQL data below')  
  
# Create a chat input box for user input  
user_input = st.chat_input("Type something...")  
# Create a button to reset the chat, which clears the messages in the session state  
if st.button('Reset Chat'):  
    st.session_state.messages = []  
  
# Initialize chat history in the session state if it doesn't exist  
if "messages" not in st.session_state:  
    st.session_state.messages = []  
  
# Initialize a thread in the session state if it doesn't exist  
if "thread" not in st.session_state:  
    st.session_state.thread = None  
  
# If the user has entered input  
if user_input:  
    # Append the user's message to the session state messages list with the role 'user'  
    st.session_state.messages.append({'role': 'user', 'content': user_input})  
  
    # Call the function to update the messages displayed in the app  
    update_messages()

    assistant = get_assistant(client)
  
    # If there is no active conversation thread  
    if st.session_state.thread == None:  
        # Create a new thread and run using the user input and the assistant ID from the environment variable  
        thread, run = create_thread_and_run(user_input, assistant.id)  
        # Store the new thread in the session state  
        st.session_state.thread = thread  
    else:  
        # If a thread already exists, submit the message to the existing thread  
        thread = st.session_state.thread  
        run = submit_message(assistant.id, thread, user_input)  
  
    # Start a new turn in the conversation  
    start_conversation_turn(run, thread)  
  
    # Get the response from the thread  
    thread_resp = get_response(thread)  
  
    # Initialize a variable for any file that might be part of the assistant's response  
    assist_file = None  
  
    # Check if the latest response from the thread contains content  
    if len(json.loads(thread_resp.json())['data'][-1]['content']) >= 1:  
        # Extract text responses from the content  
        text_res = [x for x in json.loads(thread_resp.json())['data'][-1]['content'] if 'text' in x]  
        if len(text_res) > 0:  
            text_res = text_res[0]  
            assist_msg = text_res['text']['value']  
        # Extract image file responses from the content  
        image_file = [x for x in json.loads(thread_resp.json())['data'][-1]['content'] if 'image_file' in x]  
        if len(image_file) > 0:  
            image_file = image_file[0]  
            # Retrieve the image file content using the file ID  
            assist_file = client.files.content(  
                file_id=image_file['image_file']['file_id'],  
            )  
            # Append the image to the session state messages with the role 'image'  
            st.session_state.messages.append({'role': 'image', 'content': assist_file.content})  
  
    # Append the assistant's text message to the session state messages  
    st.session_state.messages.append({'role': 'assistant', 'content': assist_msg})  
  
    # Display the assistant's message and any associated image in a chat message block  
    with st.chat_message('assistant'):  
        st.markdown(assist_msg)  
        if assist_file:  
            st.image(assist_file.content)  
  
    # Update the session state with the current thread  
    st.session_state.thread = thread  
