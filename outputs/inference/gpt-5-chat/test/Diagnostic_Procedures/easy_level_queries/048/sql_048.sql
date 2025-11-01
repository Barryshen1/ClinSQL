WITH male_age_52_62 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 52 AND 62
),
valve_procedure_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE UPPER(long_title) LIKE '%VALVE%'
    AND (UPPER(long_title) LIKE '%REPLACEMENT%' OR UPPER(long_title) LIKE '%REPAIR%')
),
counts_per_admission AS (
  SELECT
    p.subject_id,
    proc.hadm_id,
    COUNT(DISTINCT CONCAT(proc.icd_code, '-', proc.icd_version)) AS distinct_valve_proc_count
  FROM male_age_52_62 p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON p.subject_id = proc.subject_id
  JOIN valve_procedure_codes vpc
    ON proc.icd_code = vpc.icd_code
   AND proc.icd_version = vpc.icd_version
  GROUP BY p.subject_id, proc.hadm_id
),
quartiles AS (
  SELECT APPROX_QUANTILES(distinct_valve_proc_count, 4) AS quartiles
  FROM counts_per_admission
)
SELECT
  q.quartiles[SAFE_OFFSET(3)] - q.quartiles[SAFE_OFFSET(1)] AS iqr_valve_procs_per_hosp
FROM quartiles q;