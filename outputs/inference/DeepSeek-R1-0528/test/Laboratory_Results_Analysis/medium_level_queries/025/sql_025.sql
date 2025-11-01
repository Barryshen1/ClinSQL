WITH cohort AS (
  SELECT 
      p.subject_id, 
      p.gender, 
      p.anchor_age,
      p.anchor_year,
      a.hadm_id,
      a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE 
      p.gender = 'F'
      AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 58 AND 68
),
cohort_diag AS (
  SELECT DISTINCT c.*
  FROM cohort c
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE d.hadm_id = c.hadm_id
      AND (
        (d.icd_version = 9 AND (d.icd_code LIKE '7865%' OR d.icd_code LIKE '410%'))
        OR
        (d.icd_version = 10 AND (d.icd_code LIKE 'R07%' OR d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
      )
  )
),
troponin_events AS (
  SELECT 
      l.subject_id,
      l.hadm_id,
      l.charttime,
      l.valuenum AS troponin_t,
      ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  WHERE 
      l.itemid IN (51002, 51003)  -- Troponin T item IDs
      AND l.valuenum > 0.01
      AND l.hadm_id IN (SELECT hadm_id FROM cohort_diag)
),
first_troponin AS (
  SELECT 
      subject_id,
      hadm_id,
      troponin_t
  FROM troponin_events
  WHERE rn = 1
)
SELECT 
    COUNT(*) AS num_admissions,
    AVG(troponin_t) AS mean_troponin_t,
    STDDEV(troponin_t) AS std_troponin_t,
    MIN(troponin_t) AS min_troponin_t,
    MAX(troponin_t) AS max_troponin_t
FROM first_troponin;