WITH patients_with_acs AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND (d.icd_code LIKE 'I20%' OR d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%' OR d.icd_code LIKE 'I23%')
),
first_lab AS (
  SELECT l.subject_id, l.valuenum,
         ROW_NUMBER() OVER (PARTITION BY l.subject_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN patients_with_acs pwa ON l.subject_id = pwa.subject_id AND l.hadm_id = pwa.hadm_id
  WHERE l.itemid = 50911
    AND l.charttime >= pwa.admittime
)
SELECT
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY valuenum / 1000) AS median,
  (PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY valuenum / 1000) - PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY valuenum / 1000)) AS iqr
FROM (
  SELECT valuenum
  FROM first_lab
  WHERE rn = 1 AND valuenum > 14
) AS filtered_values;