package com.example.todo;

import org.springframework.web.bind.annotation.*;
import java.util.List;

@RestController
@RequestMapping("/api/todos")
@CrossOrigin(origins = "*")
public class TodoController {
    
    private final TodoRepository repository;
    
    public TodoController(TodoRepository repository) {
        this.repository = repository;
    }
    
    @GetMapping
    public List<Todo> getAll() {
        return repository.findAll();
    }
    
    @PostMapping
    public Todo create(@RequestBody Todo todo) {
        return repository.save(todo);
    }
    
    @PutMapping("/{id}")
    public Todo update(@PathVariable Long id, @RequestBody Todo todo) {
        todo.setId(id);
        return repository.save(todo);
    }
    
    @DeleteMapping("/{id}")
    public void delete(@PathVariable Long id) {
        repository.deleteById(id);
    }
}
