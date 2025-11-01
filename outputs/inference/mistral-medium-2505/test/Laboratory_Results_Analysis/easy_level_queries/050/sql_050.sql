WITH sepsis_admissions AS (
  -- Get male sepsis admissions for age 44
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age = 44
    AND d.icd_code IN ('A41.9', 'R65.20', 'A41.9', 'R65.21', 'A41.9', 'R65.22') -- Example sepsis ICD codes
),

platelet_counts AS (
  -- Get first platelet count for each admission
  SELECT
    s.hadm_id,
    l.valuenum AS platelet_count
  FROM
    sepsis_admissions s
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON s.hadm_id = l.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  WHERE
    d.label = 'Platelet Count' -- or use itemid = 51265 directly
    AND l.charttime >= s.admittime
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY s.hadm_id ORDER BY l.charttime) = 1 -- First platelet count per admission
)

-- Calculate standard deviation of platelet counts
SELECT
  STDDEV(platelet_count) AS platelet_count_stddev
FROM
  platelet_counts;