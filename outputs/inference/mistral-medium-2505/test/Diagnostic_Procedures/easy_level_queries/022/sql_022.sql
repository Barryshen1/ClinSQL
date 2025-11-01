WITH male_patients_82_92 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 82 AND 92
),

relevant_procedures AS (
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id,
    p.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
  ON
    p.icd_code = d.icd_code
    AND p.icd_version = d.icd_version
  WHERE
    p.subject_id IN (SELECT subject_id FROM male_patients_82_92)
    AND (
      p.icd_code IN ('37.8', '37.94', '02HA33Z', '02HK33Z', '02H033Z')
      OR d.long_title LIKE '%pacemaker%'
      OR d.long_title LIKE '%defibrillator%'
      OR d.long_title LIKE '%ICD%'
    )
),

procedure_counts AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS procedure_count
  FROM
    relevant_procedures
  GROUP BY
    hadm_id
)

SELECT
  MIN(procedure_count) AS min_procedures_per_hospitalization
FROM
  procedure_counts
WHERE
  procedure_count > 0;