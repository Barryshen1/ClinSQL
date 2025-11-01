WITH echocardiography_procedures AS (
  SELECT 
    p.subject_id,
    COUNT(*) AS num_echocardiography_procedures
  FROM physionet-data.mimiciv_3_1_icu.procedureevents p
  INNER JOIN physionet-data.mimiciv_3_1_icu.d_items d
    ON p.itemid = d.itemid
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients pt
    ON p.subject_id = pt.subject_id
  WHERE LOWER(d.label) LIKE '%echocardiogram%'
     OR LOWER(d.label) LIKE '%echo%'
     OR LOWER(d.label) LIKE '%transthoracic echocardiogram%'
     OR LOWER(d.label) LIKE '%tTE%'
     OR LOWER(d.label) LIKE '%echo%'
  AND pt.gender = 'F'
  AND pt.anchor_age BETWEEN 88 AND 98
  GROUP BY p.subject_id
)
SELECT PERCENTILE_CONT(num_echocardiography_procedures, 0.25) OVER () AS p25_echocardiography_procedures_per_patient
FROM echocardiography_procedures
LIMIT 1;