WITH acs_admissions AS (
  SELECT
    a.hadm_id,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE d.seq_num = 1
    AND d.icd_code IN (
      'I20.0', 'I21.0', 'I21.1', 'I21.2', 'I21.3', 'I21.4',
      'I22.0', 'I22.1', 'I22.2', 'I22.8', 'I22.9'
    )
    AND p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 67 AND 77
),
troponin_first AS (
  SELECT
    hadm_id,
    valuenum,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE itemid = 50911
    AND valuenum IS NOT NULL
)
SELECT
  CASE
    WHEN t.valuenum <= 0.04 THEN 'Normal (<=0.04)'
    WHEN t.valuenum > 0.04 AND t.valuenum <= 0.1 THEN 'Borderline (0.04-0.1)'
    WHEN t.valuenum > 0.1 THEN 'Elevated (>0.1)'
  END AS troponin_category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percent_of_admissions,
  ROUND(SUM(a.hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_rate
FROM acs_admissions a
JOIN troponin_first t
  ON a.hadm_id = t.hadm_id
  AND t.rn = 1
GROUP BY troponin_category;