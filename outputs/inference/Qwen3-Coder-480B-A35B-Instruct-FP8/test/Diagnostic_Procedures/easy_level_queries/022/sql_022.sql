WITH eligible_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 82 AND 92
),

pacemaker_procedures AS (
  SELECT
    ea.hadm_id,
    COUNT(DISTINCT picd.seq_num) AS proc_count
  FROM
    eligible_admissions ea
  JOIN
    physionet-data.mimiciv_3_1_hosp.procedures_icd picd
  ON
    ea.hadm_id = picd.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures dproc
  ON
    picd.icd_code = dproc.icd_code
    AND picd.icd_version = dproc.icd_version
  WHERE
    LOWER(dproc.long_title) LIKE '%pacemaker%'
    OR LOWER(dproc.long_title) LIKE '%implantable cardioverter defibrillator%'
  GROUP BY
    ea.hadm_id
)

SELECT
  MIN(proc_count) AS min_procedures_per_hospitalization
FROM
  pacemaker_procedures;