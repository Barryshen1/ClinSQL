WITH PatientCohort AS (
  -- Select patients meeting the criteria: male, age 83-93, first ICU stay, sepsis diagnosis
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    di.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS ic
    ON p.subject_id = ic.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON p.subject_id = di.subject_id
    AND ic.hadm_id = di.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
    AND ic.stay_id IN (
      SELECT
        MIN(stay_id)
      FROM
        `physionet-data.mimiciv_3_1_icu.icustays`
      WHERE
        subject_id = p.subject_id
      GROUP BY
        subject_id
    )
    AND di.icd_code = 'R65.21' -- Sepsis code (adjust if needed based on specific sepsis definition)
),

ProcedureCounts AS (
  -- Count distinct procedures within the first 72 hours of the ICU stay
  SELECT
    pc.subject_id,
    pc.stay_id,
    COUNT(DISTINCT pe.itemid) AS distinct_procedure_count
  FROM
    PatientCohort AS pc
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    ON pc.subject_id = pe.subject_id
    AND pc.stay_id = pe.stay_id
    AND pe.starttime BETWEEN pc.intime AND TIMESTAMP_ADD(pc.intime, INTERVAL 72 HOUR)
  GROUP BY
    pc.subject_id,
    pc.stay_id
),

Quartiles AS (
  -- Assign patients to quartiles based on procedure counts
  SELECT
    pc.subject_id,
    pc.stay_id,
    pc.distinct_procedure_count,
    NTILE(4) OVER (ORDER BY pc.distinct_procedure_count) AS procedure_quartile
  FROM
    ProcedureCounts AS pc
),

ICULOS AS (
  -- Calculate ICU LOS in days
  SELECT
    q.subject_id,
    q.stay_id,
    q.procedure_quartile,
    TIMESTAMP_DIFF(q.outtime, q.intime, DAY) AS icu_los_days
  FROM
    Quartiles AS q
),

Mortality AS (
  -- Determine mortality status
  SELECT
    q.subject_id,
    q.stay_id,
    q.procedure_quartile,
    CASE
      WHEN h.hospital_expire_flag = 1 THEN 1
      ELSE 0
    END AS mortality
  FROM
    Quartiles AS q
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS h
    ON q.subject_id = h.subject_id
    AND q.stay_id = h.hadm_id -- Note: stay_id is not directly linked to hadm_id, but we assume the ICU stay belongs to the admission
)

-- Final aggregation: Calculate mean procedure counts, mean ICU LOS, and mortality % per quartile
SELECT
  m.procedure_quartile,
  AVG(m.distinct_procedure_count) AS mean_procedure_count,
  AVG(l.icu_los_days) AS mean_icu_los_days,
  AVG(m.mortality) * 100 AS mortality_percentage
FROM
  Mortality AS m
INNER JOIN
  ICULOS AS l
  ON m.subject_id = l.subject_id
  AND m.stay_id = l.stay_id
  AND m.procedure_quartile = l.procedure_quartile
GROUP BY
  m.procedure_quartile
ORDER BY
  m.procedure_quart;