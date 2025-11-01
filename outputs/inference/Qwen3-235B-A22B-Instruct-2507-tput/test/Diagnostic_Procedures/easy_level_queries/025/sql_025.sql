WITH circulatory_support_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%iabp%'
     OR LOWER(label) LIKE '%ecmo%'
     OR LOWER(label) LIKE '%ventricular assist%'
     OR LOWER(label) LIKE '%impella%'
),
patient_procedure_counts AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT pe.itemid) AS distinct_procedure_count
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON p.subject_id = pe.subject_id
  LEFT JOIN circulatory_support_items csi
    ON pe.itemid = csi.itemid
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
  GROUP BY p.subject_id
)
SELECT MIN(distinct_procedure_count) AS min_distinct_procedures_per_patient
FROM patient_procedure_counts;