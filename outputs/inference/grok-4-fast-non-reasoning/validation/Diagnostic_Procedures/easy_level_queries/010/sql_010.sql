WITH eligible_patients AS (
  -- Filter to males aged 84-94 with ICU stays (hospitalized)
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON p.subject_id = i.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 84 AND 94
),
echo_procedures AS (
  -- Get distinct echocardiography itemids
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%echo%'
     OR LOWER(label) LIKE '%echocardiography%'
     OR LOWER(label) LIKE '%doppler%'
     OR itemid IN (220045, 220229, 220230)  -- Common echo itemids (transthoracic, etc.)
)
SELECT 
  COALESCE(MAX(distinct_echo_count), 0) AS max_distinct_echos
FROM (
  SELECT 
    pe.subject_id,
    COUNT(DISTINCT ep.itemid) AS distinct_echo_count
  FROM eligible_patients pat
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
    ON pat.subject_id = pe.subject_id
  INNER JOIN echo_procedures ep ON pe.itemid = ep.itemid
  GROUP BY pe.subject_id
);