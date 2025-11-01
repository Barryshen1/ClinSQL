WITH patient_admissions AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 76 AND 86
),
cardiac_procedures AS (
  SELECT
    pa.hadm_id,
    dip.icd_code,
    dip.long_title
  FROM
    patient_admissions pa
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.procedures_icd pi
  ON
    pa.hadm_id = pi.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.d_icd_procedures dip
  ON
    pi.icd_code = dip.icd_code
    AND pi.icd_version = dip.icd_version
  WHERE
    LOWER(dip.long_title) LIKE '%heart%'
    OR LOWER(dip.long_title) LIKE '%cardiac%'
    OR LOWER(dip.long_title) LIKE '%coronary%'
    OR LOWER(dip.long_title) LIKE '%valve%'
    OR LOWER(dip.long_title) LIKE '%bypass%'
    OR LOWER(dip.long_title) LIKE '%angioplasty%'
    OR LOWER(dip.long_title) LIKE '%pacemaker%'
    OR LOWER(dip.long_title) LIKE '%defibrillator%'
    OR LOWER(dip.long_title) LIKE '%electrophysiology%'
    OR LOWER(dip.long_title) LIKE '%arrhythmia%'
),
procedure_counts AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS distinct_cardiac_proc_count
  FROM
    cardiac_procedures
  GROUP BY
    hadm_id
)
SELECT
  PERCENTILE_CONT(distinct_cardiac_proc_count, 0.75) OVER () - PERCENTILE_CONT(distinct_cardiac_proc_count, 0.25) OVER () AS iqr
FROM
  procedure_counts
LIMIT 1;