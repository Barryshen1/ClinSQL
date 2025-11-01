WITH filtered_patients AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 79 AND 89
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.seq_num = 1
        AND (
          (d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code LIKE '4111%'))
          OR
          (d.icd_version = 10 AND (d.icd_code LIKE 'I200%' OR d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I240%'))
        )
    )
),
first_troponin AS (
  SELECT 
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  WHERE l.itemid = 50194
    AND l.valuenum IS NOT NULL
)
SELECT
  CASE 
    WHEN t.valuenum <= 0.04 THEN 'normal'
    WHEN t.valuenum <= 0.1 THEN 'borderline'
    ELSE 'elevated'
  END AS category,
  COUNT(*) AS count
FROM filtered_patients f
INNER JOIN first_troponin t
  ON f.hadm_id = t.hadm_id
WHERE t.rn = 1
GROUP BY category
ORDER BY 
  CASE category 
    WHEN 'normal' THEN 1
    WHEN 'borderline' THEN 2
    WHEN 'elevated' THEN 3
  END;