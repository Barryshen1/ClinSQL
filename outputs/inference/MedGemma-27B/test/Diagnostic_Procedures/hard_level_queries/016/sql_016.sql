WITH FirstICUStay AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  WHERE
    stay_id = 1
),
PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.subject_id IN (
      SELECT
        subject_id
      FROM FirstICUStay
    )
),
Diagnosis AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  WHERE
    d.icd_version = '9'
    AND d.icd_code LIKE '486%'
    AND d.hadm_id IN (
      SELECT
        hadm_id
      FROM FirstICUStay
    )
),
ProcedureCounts AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    COUNT(pr.seq_num) AS procedure_count
  FROM PatientInfo AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pr
    ON p.subject_id = pr.subject_id AND p.hadm_id = pr.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 88 AND 98
    AND pr.chartdate BETWEEN (
      SELECT
        intime
      FROM FirstICUStay AS f
      WHERE
        f.subject_id = p.subject_id AND f.hadm_id = p.hadm_id
    ) AND (
      SELECT
        intime
      FROM FirstICUStay AS f
      WHERE
        f.subject_id = p.subject_id AND f.hadm_id = f.hadm_id
    ) + INTERVAL '72' HOUR
  GROUP BY
    p.subject_id,
    p.hadm_id
),
ICULOS AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.los AS icu_los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS ic
  WHERE
    ic.stay_id = 1
),
Mortality AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag AS mortality
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE
    a.hadm_id IN (
      SELECT
        hadm_id
      FROM FirstICUStay
    )
)
SELECT
  NTILE(5) OVER (ORDER BY pc.procedure_count) AS procedure_quintile,
  AVG(pc.procedure_count) AS avg_procedure_count,
  AVG(ic.icu_los) AS avg_icu_los,
  AVG(m.mortality) AS mortality_percent
FROM ProcedureCounts AS pc
JOIN ICULOS AS ic
  ON pc.subject_id = ic.subject_id AND pc.had;