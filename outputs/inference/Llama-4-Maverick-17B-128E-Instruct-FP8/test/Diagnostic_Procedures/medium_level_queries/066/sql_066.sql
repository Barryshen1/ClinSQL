WITH asthma_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 88 AND 98
  AND dicd.long_title LIKE '%Asthma%'
),
admission_procedures AS (
  SELECT a.hadm_id, COUNT(p.icd_code) AS num_procedures
  FROM asthma_patients a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p ON a.hadm_id = p.hadm_id
  GROUP BY a.hadm_id
),
admission_details AS (
  SELECT a.hadm_id, 
         DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN asthma_patients ap ON a.hadm_id = ap.hadm_id
)
SELECT 
  stay_duration,
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(25)] AS percentile_25,
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(50)] AS percentile_50,
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(75)] AS percentile_75
FROM (
  SELECT 
    ap.num_procedures,
    CASE 
      WHEN ad.los BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN ad.los BETWEEN 4 AND 7 THEN '4-7 days'
    END AS stay_duration
  FROM admission_procedures ap
  INNER JOIN admission_details ad ON ap.hadm_id = ad.hadm_id
  WHERE ad.los BETWEEN 1 AND 7
)
GROUP BY stay_duration;