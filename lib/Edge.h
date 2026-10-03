#ifndef DOTWRITER_EDGE_H_
#define DOTWRITER_EDGE_H_

#include "AttributeSet.h"
#include "Idable.h"

namespace DotWriter {

class Graph;

/**
 * Represents an edge in a graph.
 */
class Edge {
private:
  Node * _src;
  Node * _dst;
  std::string _label;
  bool _is_html_label;
  EdgeAttributeSet _attributes;

  Edge(Node * src, Node * dst, const std::string &label, bool is_html_label);

public:
  Edge(Node * src, Node * dst, const std::string &label = "");
  Edge(Node * src, Node * dst, const HtmlString &label);

  virtual ~Edge() {};

  Node * GetSource() {
    return _src;
  }

  Node * GetDest() {
    return _dst;
  }

  const std::string& GetLabel() {
    return _label;
  }

  void SetLabel(const std::string &label) {
    _label = label;
    _is_html_label = false;
  };

  void SetLabel(const HtmlString &label) {
    _label = static_cast<std::string>(label);
    _is_html_label = true;
  };

  /**
   * Returns the set of attributes for this edge.
   * Manipulate this object to change the style of this edge.
   */
  EdgeAttributeSet& GetAttributes() {
    return _attributes;
  }

  void Print(bool isDirected, std::ostream& out);
};

}  // namespace DotWriter

#endif
