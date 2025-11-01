WITH PatientTIA AS (
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    d.icd_code = 'I63' -- TIA code
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
),
AdmissionTIA AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN PatientTIA AS pt
    ON a.subject_id = pt.subject_id
),
ICUStay AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los
  FROM AdmissionTIA AS a
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS ic
    ON a.hadm_id = ic.hadm_id
),
ProcedureCount AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    COUNT(DISTINCT pe.itemid) AS procedure_count
  FROM AdmissionTIA AS a
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    ON a.hadm_id = pe.hadm_id
  WHERE
    pe.itemid IN (
      SELECT
        itemid
      FROM `physionet-data.mimiciv_3_1_icu.d_items`
      WHERE
        label LIKE '%ultrasound%' OR label LIKE '%echocardiogram%'
    )
  GROUP BY
    a.hadm_id,
    a.subject_id
),
AdmissionLength AS (
  SELECT
    hadm_id,
    subject_id,
    -- Calculate admission length in days
    -- Use TIMESTAMP_DIFF for accurate day calculation
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS admission_length_days
  FROM AdmissionTIA
  WHERE
    dischtime IS NOT NULL
    AND admittime IS NOT NULL
)
SELECT
  pc.procedure_count,
  CASE
    WHEN ic.stay_id IS NOT NULL THEN 'ICU Used'
    ELSE 'No ICU'
  END AS icu_use,
  AVG(pc.procedure_count) AS mean_procedures
FROM ProcedureCount AS pc
JOIN AdmissionLength AS al
  ON pc.hadm_id = al.hadm_id
LEFT JOIN ICUStay AS ic
  ON pc.hadm_id = ic.hadm_id
WHERE
  al.admission_length_days BETWEEN 1 AND 7
  AND pc.procedure_count BETWEEN 1 AND 7
GROUP BY
  pc.procedure_count,
  icu_use
ORDER BY
  pc.procedure_count;