# Rover
Event Pickup Management System

Description:
The Event Pickup Management System is a comprehensive Flask-based application designed to streamline the process of managing event pickups, driver assignments, and user registrations. This system provides a user-friendly interface for event organizers, drivers, and attendees to efficiently coordinate transportation logistics for various events.

Key Features:

User Registration and Authentication: Users can create accounts, log in securely, and manage their profiles.
Event Management: Organizers can create, update, and cancel events, while attendees can view event details and register for pickups.
Driver Management: Bus drivers can register, log in, and view their assigned pickups.
Pickup Scheduling: Attendees can schedule pickups for events, specifying their location and desired pickup time.
Route Calculation: The system calculates optimal routes for drivers using Dijkstra's Algorithm, ensuring efficient transportation for attendees.
Real-Time Notifications: Attendees and drivers receive real-time notifications for pickup confirmations, updates, and cancellations.
How to Use:

Clone the repository to your local machine.
Install the required dependencies using pip install -r requirements.txt.
Configure the database settings in config.py.
Run the application using python app.py.
Access the application through your web browser at http://localhost:5000.

Roadmap:

Implement an admin dashboard for managing users, events, and drivers.
Enhance the user interface for improved usability and accessibility.
Integrate a mapping API for visualizing event locations and driver routes.
Expand the notification system to support email and SMS notifications.
License:
This project is licensed under the MIT License. See the LICENSE file for details.

Feedback and Support:
If you have any questions, suggestions, or encounter any issues while using the application, please don't hesitate to open an issue on GitHub or reach out to the project maintainers.
