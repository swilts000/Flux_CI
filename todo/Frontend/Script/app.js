// Frontend script for the Todo app
// - Communicates with backend endpoints under /api/todos
// - Provides functions to load, add and delete todos
// - Shows brief notifications for success / error events

const API_URL = "/api/todos"; // Base API endpoint for todo operations

/**
 * Show a transient notification message in the page.
 * @param {string} message - The message text to display.
 * @param {string} type - The type of notification (e.g. "success", "error").
 */
function showNotification(message, type) {
    const notification = document.getElementById("notification");

    // Defensive: if the notification element is missing, silently fail.
    if (!notification) return;

    // Set content and class for styling and visibility.
    notification.textContent = message;
    notification.className = `notification ${type} show`;

    console.log(`[${type.toUpperCase()}] ${message}`);

    // Remove the temporary 'show' flag after a short delay so it hides again.
    setTimeout(() => {
        // Reset to the base notification class (removes type/show modifiers).
        notification.className = "notification";
    }, 3000);
}

/**
 * Parse error response from backend.
 * @param {Response} response - The fetch response object.
 * @returns {Promise<string>} - The error message.
 */
async function parseErrorResponse(response) {
    try {
        const data = await response.json();
        return data.error || `HTTP Error ${response.status}`;
    } catch (e) {
        return `HTTP Error ${response.status}`;
    }
}

/**
 * Fetch todos from the backend and render them into the #todoList element.
 * Each todo becomes a clickable <li> which deletes that todo when clicked.
 */
async function loadTodos() {
    try {
        // Request todos from the backend API.
        const res = await fetch(API_URL);

        if (!res.ok) {
            const errorMsg = await parseErrorResponse(res);
            throw new Error(errorMsg);
        }

        // Parse JSON response (expected to be an array of todos).
        const todos = await res.json();

        // Find the list element and clear current contents.
        const list = document.getElementById("todoList");
        if (!list) {
            showNotification("Todo list element not found.", "error");
            return;
        }

        list.innerHTML = "";

        // If there are no todos, optionally show a placeholder list item.
        if (!Array.isArray(todos) || todos.length === 0) {
            const placeholder = document.createElement("li");
            placeholder.textContent = "No todos yet. Add one!";
            placeholder.className = "placeholder";
            list.appendChild(placeholder);
            return;
        }

        // Render each todo as a list item. Clicking a todo will delete it.
        todos.forEach(t => {
            const li = document.createElement("li");
            li.textContent = t.text;
            li.title = "Click to delete"; // small UX hint

            li.onclick = async () => {
                try {
                    // Send DELETE request to backend for the clicked todo.
                    const deleteRes = await fetch(`${API_URL}/${t.id}`, { method: "DELETE" });

                    if (!deleteRes.ok) {
                        const errorMsg = await parseErrorResponse(deleteRes);
                        throw new Error(errorMsg);
                    }

                    showNotification("Todo deleted successfully!", "success");

                    // Reload the list after deletion to reflect changes.
                    loadTodos();
                } catch (error) {
                    showNotification(`Error deleting todo: ${error.message}`, "error");
                }
            };

            list.appendChild(li);
        });

        // Show success message when todos are loaded
        if (todos.length > 0) {
            console.log(`Successfully loaded ${todos.length} todo(s)`);
        }
    } catch (error) {
        showNotification(`Error loading todos: ${error.message}`, "error");
    }
}

/**
 * Read the value from the #todoInput field and POST a new todo to the backend.
 * After successful creation, the input is cleared and todos are reloaded.
 */
async function addTodo() {
    const input = document.getElementById("todoInput");

    // Defensive: ensure the input field exists and contains non-empty text.
    if (!input) {
        showNotification("Todo input element not found.", "error");
        return;
    }

    const text = input.value.trim();
    if (!text) {
        showNotification("Please enter a todo before submitting.", "error");
        return; // don't submit empty todos
    }

    try {
        const res = await fetch(API_URL, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ text, done: false })
        });

        if (!res.ok) {
            const errorMsg = await parseErrorResponse(res);
            throw new Error(errorMsg);
        }

        const savedTodo = await res.json();
        showNotification(`✓ Todo added successfully! (ID: ${savedTodo.id})`, "success");

        // Clear the input and reload the list to include the new todo.
        input.value = "";
        loadTodos();
    } catch (error) {
        showNotification(`Error adding todo: ${error.message}`, "error");
    }
}

// Load todos when the page finishes loading. Keeps behavior identical to before.
window.addEventListener('DOMContentLoaded', loadTodos);
