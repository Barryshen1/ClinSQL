WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 51 AND 61
),
ecg_telemetry_procs AS (
  SELECT p.subject_id,
         p.icd_code,
         p.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code
   AND p.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%ecg%'
     OR LOWER(d.long_title) LIKE '%telemetry%'
),
proc_counts AS (
  SELECT ep.subject_id,
         COUNT(DISTINCT et.icd_code) AS distinct_procedure_count
  FROM eligible_patients ep
  JOIN ecg_telemetry_procs et
    ON ep.subject_id = et.subject_id
  GROUP BY ep.subject_id
)
SELECT APPROX_QUANTILES(distinct_procedure_count, 100)[OFFSET(25)] AS percentile_25
FROM proc_counts;