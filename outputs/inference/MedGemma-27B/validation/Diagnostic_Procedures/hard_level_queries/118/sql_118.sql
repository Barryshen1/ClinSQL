WITH relevant_patients AS (
  -- Select patients matching the criteria: female, age 44-54, AMI diagnosis
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    di.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON p.subject_id = di.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND di.icd_code = 'I21.9' -- AMI code
),
icu_admissions AS (
  -- Select ICU admissions for the relevant patients
  SELECT
    rp.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los
  FROM
    relevant_patients AS rp
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS ic
    ON rp.subject_id = ic.subject_id
),
procedures_in_first_72h AS (
  -- Select procedures performed within the first 72 hours of ICU stay
  SELECT
    ia.hadm_id,
    ia.stay_id,
    pe.starttime,
    pe.endtime
  FROM
    icu_admissions AS ia
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    ON ia.hadm_id = pe.hadm_id AND ia.stay_id = pe.stay_id
  WHERE
    pe.starttime BETWEEN ia.intime AND TIMESTAMP_ADD(ia.intime, INTERVAL 72 HOUR)
),
procedure_counts AS (
  -- Count the number of procedures per ICU stay
  SELECT
    hadm_id,
    stay_id,
    COUNT(*) AS procedure_count
  FROM
    procedures_in_first_72h
  GROUP BY
    hadm_id,
    stay_id
),
quartiles AS (
  -- Calculate quartiles based on procedure count
  SELECT
    hadm_id,
    stay_id,
    procedure_count,
    NTILE(4) OVER (ORDER BY procedure_count) AS procedure_quartile
  FROM
    procedure_counts
),
hospital_los AS (
  -- Calculate hospital LOS for each admission
  SELECT
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS hospital_los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE
    hadm_id IN (SELECT DISTINCT hadm_id FROM icu_admissions)
),
mortality AS (
  -- Determine in-hospital mortality
  SELECT
    hadm_id,
    hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE
    hadm_id IN (SELECT DISTINCT hadm_id FROM icu_admissions)
)
-- Final result: Stratify by procedure quartile and report statistics
SELECT
  q.procedure_quartile,
  COUNT(DISTINCT q.hadm_id) AS n_per_quartile,
  AVG(q.procedure_count) AS mean_procedure_count,
  AVG(h.hospital_los) AS mean_hospital_los,
  AVG(CASE WHEN m.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100 AS mortality_percent
FROM
  quartiles AS q
LEFT JOIN
  hospital_los AS h
  ON q.hadm_id = h.hadm_id
LEFT JOIN
  mortality AS m
  ON q.hadm_id = m.hadm_id
GROUP BY
  q.procedure_quartile
ORDER BY
  q.procedure_quartile;