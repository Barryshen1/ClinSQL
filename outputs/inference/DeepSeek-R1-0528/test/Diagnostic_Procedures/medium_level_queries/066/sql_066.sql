WITH asthma_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE REGEXP_CONTAINS(LOWER(long_title), r'\basthma\b')
),
patient_admissions AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age, 
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 88 AND 98
),
asthma_admissions AS (
  SELECT pa.*
  FROM patient_admissions pa
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    INNER JOIN asthma_codes ac 
      ON di.icd_code = ac.icd_code AND di.icd_version = ac.icd_version
    WHERE pa.hadm_id = di.hadm_id
  )
),
procedure_counts AS (
  SELECT 
    aa.hadm_id,
    DATE_DIFF(aa.dischtime, aa.admittime, DAY) AS los_days,
    COUNT(dh.code) AS num_diag_procedures
  FROM asthma_admissions aa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` he
    ON aa.hadm_id = he.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh
    ON he.hcpcs_cd = dh.code
    AND LOWER(dh.long_description) LIKE '%diagnostic%'
  GROUP BY aa.hadm_id, aa.admittime, aa.dischtime
),
categorized AS (
  SELECT 
    hadm_id,
    num_diag_procedures,
    CASE 
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
    END AS los_group
  FROM procedure_counts
  WHERE los_days BETWEEN 1 AND 7
)
SELECT 
  los_group,
  approx_quantiles_arr[OFFSET(1)] AS p25,
  approx_quantiles_arr[OFFSET(2)] AS p50,
  approx_quantiles_arr[OFFSET(3)] AS p75
FROM (
  SELECT 
    los_group,
    APPROX_QUANTILES(num_diag_procedures, 4) AS approx_quantiles_arr
  FROM categorized
  WHERE los_group IS NOT NULL
  GROUP BY los_group
);