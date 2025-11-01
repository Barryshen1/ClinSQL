WITH troponin_items AS (
  -- Identify all troponin T itemids
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),

first_trop AS (
  -- Pick the first troponin T result in the first 24h of admission
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN troponin_items ti
    ON le.itemid = ti.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON le.hadm_id = a.hadm_id
  WHERE
    le.charttime BETWEEN a.admittime AND a.admittime + INTERVAL 24 HOUR
    AND le.valuenum IS NOT NULL
),

index_trop AS (
  -- Only keep the index (first) troponin T per admission
  SELECT
    ft.subject_id,
    ft.hadm_id,
    ft.valuenum
  FROM first_trop ft
  WHERE ft.rn = 1
),

cohort AS (
  -- Define the cohort: males aged 87-97 at admission, emergency admissions with an index trop
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag,
    it.valuenum AS trop_value,
    CASE
      WHEN it.valuenum <= 0.03 THEN 'Normal/Minimal'
      WHEN it.valuenum > 0.03 AND it.valuenum <= 0.1 THEN 'Borderline'
      ELSE 'Elevated'
    END AS trop_category
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN index_trop it
    ON a.hadm_id = it.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 87 AND 97
    AND a.admission_type = 'EMERGENCY'
),

totals AS (
  -- Compute total cohort size
  SELECT COUNT(*) AS total_n
  FROM cohort
)

-- Final aggregation by troponin category
SELECT
  c.trop_category,
  COUNT(*) AS n,
  ROUND(100 * COUNT(*) / ANY_VALUE(t.total_n), 1) AS percent_of_cohort,
  ROUND(100 * SUM(c.hospital_expire_flag) / COUNT(*), 1) AS in_hospital_mortality_percent
FROM cohort c
CROSS JOIN totals t
GROUP BY c.trop_category
ORDER BY
  CASE c.trop_category
    WHEN 'Normal/Minimal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Elevated' THEN 3
  END;