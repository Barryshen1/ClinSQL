WITH pacemaker_patients AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT CONCAT(proc.icd_code, '-', proc.icd_version)) AS distinct_proc_count
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON p.subject_id = proc.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dproc
    ON proc.icd_code = dproc.icd_code
    AND proc.icd_version = dproc.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
    AND (
      UPPER(dproc.long_title) LIKE '%PACEMAKER%'
      OR UPPER(dproc.long_title) LIKE '%DEFIBRILLATOR%'
    )
  GROUP BY p.subject_id
)
SELECT
  APPROX_QUANTILES(distinct_proc_count, 100)[OFFSET(25)] AS p25_distinct_proc_count
FROM pacemaker_patients;