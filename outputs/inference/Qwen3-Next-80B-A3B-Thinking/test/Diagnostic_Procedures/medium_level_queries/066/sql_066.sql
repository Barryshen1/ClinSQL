WITH asthma_admissions AS (
  SELECT DISTINCT a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd 
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
    AND d_icd.long_title LIKE '%asthma%'
),

procedure_counts AS (
  SELECT aa.hadm_id, COUNT(pi.hadm_id) AS procedure_count, aa.admittime, aa.dischtime
  FROM asthma_admissions aa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi 
    ON aa.hadm_id = pi.hadm_id
  GROUP BY aa.hadm_id, aa.admittime, aa.dischtime
),

los_data AS (
  SELECT procedure_count,
         DATE_DIFF(dischtime, admittime, DAY) AS los_days
  FROM procedure_counts
  WHERE DATE_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 7
)

SELECT 
  CASE 
    WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
  END AS stay_group,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY procedure_count) AS p25,
  PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY procedure_count) AS p50,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY procedure_count) AS p75
FROM los_data
GROUP BY stay_group;