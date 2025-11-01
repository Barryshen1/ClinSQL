WITH male_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING (subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 82 AND 92
),
implant_procs AS (
  SELECT
    pi.subject_id,
    pi.hadm_id,
    pi.icd_code,
    d.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
      ON pi.icd_code = d.icd_code
      AND pi.icd_version = d.icd_version
    JOIN male_admissions ma
      ON pi.subject_id = ma.subject_id
      AND pi.hadm_id = ma.hadm_id
  WHERE
    -- keywords to identify pacemaker / ICD implantation procedures
    (
      LOWER(d.long_title) LIKE '%pacemaker%'
      OR LOWER(d.long_title) LIKE '%defibrill%'           -- defibrillator / defibrillation
      OR LOWER(d.long_title) LIKE '%implantable cardioverter%'
      OR LOWER(d.long_title) LIKE '%automatic implantable%'
      OR LOWER(d.long_title) LIKE '%aicd%'
      OR LOWER(d.long_title) LIKE '%cardiac resynchronization%'
    )
),
per_hadm_counts AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS num_distinct_implants
  FROM
    implant_procs
  GROUP BY
    hadm_id
)
SELECT
  MIN(num_distinct_implants) AS min_distinct_implant_procedures_per_hospitalization
FROM
  per_hadm_counts;