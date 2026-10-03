#ifndef DOTWRITER_NODE_H_
#define DOTWRITER_NODE_H_

#include <ostream>
#include <string>

#include "AttributeSet.h"
#include "Idable.h"

namespace DotWriter {

/**
 * Represents a node in a graph.
 */
class Node : public Idable {
private:
  std::string _label;
  bool _is_html_label;
  NodeAttributeSet _attributes;

  Node(const std::string& id, const std::string &label, bool is_html_label) :
    Idable(id),
    _label(label),
    _is_html_label(is_html_label)
  {}

public:
  Node(const std::string& id, const std::string &label = "") :
    Node(id, label, false)
  {}
  
  Node(const std::string& id, const HtmlString &label) :
    Node(id, static_cast<std::string>(label), true)
  {}

  virtual ~Node() {};

  void Print(std::ostream& out);

  /** Simple getters / setters **/
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

  NodeAttributeSet& GetAttributes() {
    return _attributes;
  }
};

}  // namespace DotWriter

#endif
