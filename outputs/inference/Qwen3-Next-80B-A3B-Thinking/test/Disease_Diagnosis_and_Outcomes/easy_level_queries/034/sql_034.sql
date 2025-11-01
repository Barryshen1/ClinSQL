WITH filtered_admissions AS (
  SELECT
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 40 AND 50
    AND (LOWER(di.long_title) LIKE '%sepsis%' OR LOWER(di.long_title) LIKE '%septic shock%')
)
SELECT
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY los) - 
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY los) AS iqr
FROM (
  SELECT
    DATE_DIFF(dischtime, admittime, DAY) AS los
  FROM filtered_admissions
) AS los_data;