WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) AS admittime_year,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 82 AND 92
),
procedure_filtered AS (
  SELECT
    pa.hadm_id,
    d.long_title
  FROM
    patient_admissions pa
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.procedures_icd pi
  ON
    pa.hadm_id = pi.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.d_icd_procedures d
  ON
    pi.icd_code = d.icd_code
    AND pi.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%pacemaker%'
    OR LOWER(d.long_title) LIKE '%implantable defibrillator%'
    OR LOWER(d.long_title) LIKE '%icd%'
),
procedure_counts AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT long_title) AS distinct_procedure_count
  FROM
    procedure_filtered
  GROUP BY
    hadm_id
)
SELECT
  MIN(distinct_procedure_count) AS min_distinct_procedures_per_hospitalization
FROM
  procedure_counts;