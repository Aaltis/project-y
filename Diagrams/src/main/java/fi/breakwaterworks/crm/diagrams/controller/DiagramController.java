package fi.breakwaterworks.crm.diagrams.controller;

import fi.breakwaterworks.crm.diagrams.model.Diagram;
import fi.breakwaterworks.crm.diagrams.model.DiagramEdge;
import fi.breakwaterworks.crm.diagrams.model.DiagramNode;
import fi.breakwaterworks.crm.diagrams.repository.DiagramEdgeRepository;
import fi.breakwaterworks.crm.diagrams.repository.DiagramNodeRepository;
import fi.breakwaterworks.crm.diagrams.repository.DiagramRepository;
import jakarta.transaction.Transactional;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import lombok.Data;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/diagrams")
@RequiredArgsConstructor
public class DiagramController {

    private final DiagramRepository diagramRepository;
    private final DiagramNodeRepository nodeRepository;
    private final DiagramEdgeRepository edgeRepository;

    // -------------------------------------------------------------------------
    // GET /api/diagrams  — list caller's diagrams (crm_admin sees all)
    // -------------------------------------------------------------------------
    @GetMapping
    public ResponseEntity<List<Diagram>> list(Authentication auth) {
        String sub = sub(auth);
        boolean isAdmin = auth.getAuthorities().stream()
                .anyMatch(a -> a.getAuthority().equals("ROLE_crm_admin"));
        List<Diagram> result = isAdmin
                ? diagramRepository.findAll()
                : diagramRepository.findByOwnerId(sub);
        return ResponseEntity.ok(result);
    }

    // -------------------------------------------------------------------------
    // POST /api/diagrams  — create empty diagram
    // -------------------------------------------------------------------------
    @PostMapping
    public ResponseEntity<Diagram> create(@Valid @RequestBody CreateDiagramRequest body,
                                          Authentication auth) {
        Diagram d = new Diagram();
        d.setName(body.getName());
        d.setOwnerId(sub(auth));
        return ResponseEntity.ok(diagramRepository.save(d));
    }

    // -------------------------------------------------------------------------
    // GET /api/diagrams/{id}  — get diagram with nodes and edges
    // -------------------------------------------------------------------------
    @GetMapping("/{id}")
    public ResponseEntity<DiagramDetail> get(@PathVariable UUID id, Authentication auth) {
        return diagramRepository.findById(id)
                .filter(d -> canAccess(d, auth))
                .map(d -> ResponseEntity.ok(new DiagramDetail(
                        d,
                        nodeRepository.findByDiagramId(id),
                        edgeRepository.findByDiagramId(id))))
                .orElse(ResponseEntity.notFound().build());
    }

    // -------------------------------------------------------------------------
    // PUT /api/diagrams/{id}  — rename
    // -------------------------------------------------------------------------
    @PutMapping("/{id}")
    public ResponseEntity<Diagram> rename(@PathVariable UUID id,
                                          @Valid @RequestBody CreateDiagramRequest body,
                                          Authentication auth) {
        return diagramRepository.findById(id)
                .filter(d -> canAccess(d, auth))
                .map(d -> {
                    d.setName(body.getName());
                    d.setUpdatedAt(LocalDateTime.now());
                    return ResponseEntity.ok(diagramRepository.save(d));
                })
                .orElse(ResponseEntity.notFound().build());
    }

    // -------------------------------------------------------------------------
    // DELETE /api/diagrams/{id}  — delete diagram + all nodes/edges (cascade)
    // -------------------------------------------------------------------------
    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(@PathVariable UUID id, Authentication auth) {
        var diagram = diagramRepository.findById(id)
                .filter(d -> canAccess(d, auth))
                .orElse(null);
        if (diagram == null) return ResponseEntity.notFound().build();
        diagramRepository.delete(diagram);
        return ResponseEntity.noContent().build();
    }

    // -------------------------------------------------------------------------
    // PUT /api/diagrams/{id}/canvas  — atomic full canvas save
    // Replaces all nodes and edges for the diagram in one transaction.
    // -------------------------------------------------------------------------
    @PutMapping("/{id}/canvas")
    @Transactional
    public ResponseEntity<DiagramDetail> saveCanvas(@PathVariable UUID id,
                                                    @Valid @RequestBody CanvasSaveRequest body,
                                                    Authentication auth) {
        return diagramRepository.findById(id)
                .filter(d -> canAccess(d, auth))
                .map(d -> {
                    nodeRepository.deleteByDiagramId(id);
                    edgeRepository.deleteByDiagramId(id);

                    List<DiagramNode> nodes = body.getNodes().stream().map(n -> {
                        DiagramNode node = new DiagramNode();
                        node.setDiagramId(id);
                        node.setNodeKey(n.getNodeKey());
                        node.setEntityType(n.getEntityType());
                        node.setEntityId(n.getEntityId());
                        node.setLabel(n.getLabel());
                        node.setX(n.getX() != null ? n.getX() : 0.0);
                        node.setY(n.getY() != null ? n.getY() : 0.0);
                        node.setColor(n.getColor());
                        node.setShape(n.getShape() != null ? n.getShape() : "RECTANGLE");
                        return node;
                    }).toList();

                    List<DiagramEdge> edges = body.getEdges().stream().map(e -> {
                        DiagramEdge edge = new DiagramEdge();
                        edge.setDiagramId(id);
                        edge.setSourceKey(e.getSourceKey());
                        edge.setTargetKey(e.getTargetKey());
                        edge.setLabel(e.getLabel());
                        edge.setStyle(e.getStyle() != null ? e.getStyle() : "SOLID");
                        return edge;
                    }).toList();

                    nodeRepository.saveAll(nodes);
                    edgeRepository.saveAll(edges);

                    d.setUpdatedAt(LocalDateTime.now());
                    diagramRepository.save(d);

                    return ResponseEntity.ok(new DiagramDetail(d, nodes, edges));
                })
                .orElse(ResponseEntity.notFound().build());
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------
    private String sub(Authentication auth) {
        if (auth.getPrincipal() instanceof Jwt jwt) return jwt.getSubject();
        return auth.getName();
    }

    private boolean canAccess(Diagram d, Authentication auth) {
        boolean isAdmin = auth.getAuthorities().stream()
                .anyMatch(a -> a.getAuthority().equals("ROLE_crm_admin"));
        return isAdmin || d.getOwnerId().equals(sub(auth));
    }

    // -------------------------------------------------------------------------
    // DTOs
    // -------------------------------------------------------------------------
    @Data
    static class CreateDiagramRequest {
        @NotBlank
        private String name;
    }

    @Data
    static class NodeDto {
        @NotBlank
        private String nodeKey;
        private String entityType;
        private UUID entityId;
        private String label;
        private Double x;
        private Double y;
        private String color;
        private String shape;
    }

    @Data
    static class EdgeDto {
        @NotBlank
        private String sourceKey;
        @NotBlank
        private String targetKey;
        private String label;
        private String style;
    }

    @Data
    static class CanvasSaveRequest {
        private List<NodeDto> nodes = List.of();
        private List<EdgeDto> edges = List.of();
    }

    record DiagramDetail(Diagram diagram, List<DiagramNode> nodes, List<DiagramEdge> edges) {}
}
