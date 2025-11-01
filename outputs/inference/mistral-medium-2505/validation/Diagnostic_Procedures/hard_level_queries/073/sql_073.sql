WITH
-- Get male patients aged 90-100
elderly_males AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 90 AND 100
),

-- Get hepatic failure patients (first ICU stay)
hepatic_failure_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime,
    TIMESTAMP_DIFF(i.outtime, i.intime, SECOND)/86400 AS los_days,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    elderly_males e
    ON a.subject_id = e.subject_id
  WHERE
    -- Hepatic failure ICD codes
    (d.icd_code IN ('572.2', '572.4', 'K72.0', 'K72.1', 'K72.9') OR
     d.icd_code LIKE '572.2%' OR d.icd_code LIKE '572.4%' OR
     d.icd_code LIKE 'K72.0%' OR d.icd_code LIKE 'K72.1%' OR d.icd_code LIKE 'K72.9%')
    -- First ICU stay per patient
    AND i.stay_id = (
      SELECT MIN(stay_id)
      FROM `physionet-data.mimiciv_3_1_icu.icustays`
      WHERE subject_id = i.subject_id
    )
),

-- Get diagnostic procedures in first 72 hours of ICU stay
diagnostic_procedures AS (
  SELECT
    h.subject_id,
    h.stay_id,
    COUNT(DISTINCT p.icd_code) AS procedure_count
  FROM
    hepatic_failure_patients h
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON h.subject_id = p.subject_id AND h.hadm_id = p.hadm_id
  WHERE
    -- Diagnostic procedure codes (ICD-9: 87.xx-89.xx; ICD-10: 0Bxx, 0Cxx, 0Dxx)
    (p.icd_code BETWEEN '8700' AND '8999' OR
     p.icd_code LIKE '0B%' OR p.icd_code LIKE '0C%' OR p.icd_code LIKE '0D%')
    -- Within 72 hours of ICU admission
    AND TIMESTAMP_DIFF(p.chartdate, h.icu_intime, HOUR) <= 72
  GROUP BY
    h.subject_id, h.stay_id
),

-- Create quartiles based on procedure counts
quartiles AS (
  SELECT
    subject_id,
    stay_id,
    procedure_count,
    NTILE(4) OVER (ORDER BY procedure_count) AS quartile
  FROM
    diagnostic_procedures
)

-- Final aggregation
SELECT
  quartile,
  COUNT(DISTINCT q.subject_id) AS patient_count,
  MIN(q.procedure_count) AS min_procedures,
  MAX(q.procedure_count) AS max_procedures,
  ROUND(AVG(q.procedure_count), 2) AS mean_procedures,
  ROUND(AVG(h.los_days), 2) AS mean_los_days,
  ROUND(100 * SUM(CASE WHEN h.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT q.subject_id), 2) AS mortality_percentage
FROM
  quartiles q
JOIN
  hepatic_failure_patients h
  ON q.subject_id = h.subject_id AND q.stay_id = h.stay_id
GROUP BY
  quartile
ORDER BY
  quartile;