## Trestle Phone Validation App (Setup and Run Instructions) 

With Trestle's Phone Validation App, validate phone numbers, determine carrier name, line type, and prepaid status, and identify disconnected phone numbers with a phone activity score.


## Registering for Trial version

Since this App uses an external access function to call Phone Validation in real-time (and ensure up-to-date accurate status), you will need an API Key from Trestle. To do that, please visit - [trestleiq.com](https://trestleiq.com) and sign-up for a free trial. This should provide you access to an API Key with 25 free queries you can use to try out the Phone Validation API.



## Using the Application after Installation

To interact with the application after it has successfully installed in your account, switch to the role which owns the application.


### Setting up Secret and External Access Integration (EAI)

Go to Security panel (top right, with security icon), add secret and then link it with EAI.


To add Secret: 

The Secret here is Trestle's Phone Validation API Key that we signed-up for in the step above. To configure it for the app, 
Go to **Security** --> **Connections** --> **Credentials** --> Add secret (API Key) and save.

To review and activate External Access Integration: 

**Security** --> **Connections** --> **Connections** --> Review and Accept

### Initializing the app

Run the procedure- 
```
call code_schema.create_eai_objects();
```



## Calling the App function

This function is a UDTF (user defined table function) which only takes one argument. 
Pass the array of phone numbers (array format using array_agg) to the function argument. 
```
select * from table(trestle.public.validate_phone(select array_agg(phone) from table_with_phone_nos));
```

## Granting Access to other Roles

In the Snowflake UI Switch to Role Accountadmin from bottom left menu. 
Now, in the Snowflake UI go to **Data Products** --> **Apps** --> Select App **Validate Phone** --> Click on **Manage Access** --> Now add all the roles to which you want to give access.
