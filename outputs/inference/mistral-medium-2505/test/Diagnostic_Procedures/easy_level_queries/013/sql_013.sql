WITH female_patients_57_67 AS (
  SELECT
    p.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 57 AND 67
),

valve_procedures AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    COUNT(DISTINCT pr.icd_code) AS num_valve_procedures
  FROM
    female_patients_57_67 p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON p.hadm_id = pr.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON pr.icd_code = d.icd_code
    AND pr.icd_version = d.icd_version
  WHERE
    -- Filter for valve repair/replacement procedures
    LOWER(d.long_title) LIKE '%valve%'
    AND (LOWER(d.long_title) LIKE '%repair%' OR LOWER(d.long_title) LIKE '%replacement%')
  GROUP BY
    p.subject_id, p.hadm_id
)

SELECT
  MIN(num_valve_procedures) AS min_valve_procedures_per_hospitalization
FROM
  valve_procedures
WHERE
  num_valve_procedures > 0;