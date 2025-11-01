WITH filtered_admissions AS (
  SELECT
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_icd
    ON a.subject_id = d_icd.subject_id AND a.hadm_id = d_icd.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON d_icd.icd_code = d.icd_code AND d_icd.icd_version = d.icd_version
  WHERE d_icd.seq_num = 1
    AND p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 59 AND 69
    AND (d.long_title LIKE '%ischemic%' OR d.long_title LIKE '%cerebral infarction%')
)
SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los_days) AS median_los
FROM (
  SELECT DATE_DIFF(dischtime, admittime, DAY) AS los_days
  FROM filtered_admissions
);