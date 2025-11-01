WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    pat.anchor_age,
    pat.gender
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 40 AND 50
),

hemorrhagic_stroke_patients AS (
  SELECT DISTINCT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    1 AS hemorrhagic_stroke
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      ON c.subject_id = dx.subject_id AND c.hadm_id = dx.hadm_id
  WHERE
    (
      (dx.icd_version = 9 AND dx.icd_code IN ('430', '431', '432'))
      OR
      (dx.icd_version = 10 AND dx.icd_code LIKE 'I60%' OR dx.icd_code LIKE 'I61%' OR dx.icd_code LIKE 'I62%')
    )
),

cohort_with_stroke_flag AS (
  SELECT
    c.*,
    IF(hsp.hemorrhagic_stroke = 1, 1, 0) AS hemorrhagic_stroke
  FROM
    cohort c
    LEFT JOIN hemorrhagic_stroke_patients hsp
      ON c.subject_id = hsp.subject_id AND c.hadm_id = hsp.hadm_id AND c.stay_id = hsp.stay_id
),

diagnostic_procedures AS (
  SELECT
    proc.subject_id,
    proc.hadm_id,
    cwsf.stay_id,
    proc.chartdate,
    proc.icd_code,
    proc.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    JOIN cohort_with_stroke_flag cwsf
      ON proc.subject_id = cwsf.subject_id AND proc.hadm_id = cwsf.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dproc
      ON proc.icd_code = dproc.icd_code AND proc.icd_version = dproc.icd_version
  WHERE
    LOWER(dproc.long_title) LIKE '%diagnostic%'
    AND proc.chartdate >= cwsf.intime
    AND proc.chartdate < TIMESTAMP_ADD(cwsf.intime, INTERVAL 72 HOUR)
),

diagnostic_procedure_counts AS (
  SELECT
    cwsf.subject_id,
    cwsf.hadm_id,
    cwsf.stay_id,
    cwsf.hemorrhagic_stroke,
    cwsf.los,
    COUNT(DISTINCT dp.icd_code) AS num_diagnostic_procedures
  FROM
    cohort_with_stroke_flag cwsf
    LEFT JOIN diagnostic_procedures dp
      ON cwsf.subject_id = dp.subject_id AND cwsf.hadm_id = dp.hadm_id AND cwsf.stay_id = dp.stay_id
  GROUP BY
    cwsf.subject_id, cwsf.hadm_id, cwsf.stay_id, cwsf.hemorrhagic_stroke, cwsf.los
),

mortality AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
),

final AS (
  SELECT
    dpc.hemorrhagic_stroke,
    dpc.num_diagnostic_procedures,
    dpc.los,
    m.hospital_expire_flag
  FROM
    diagnostic_procedure_counts dpc
    LEFT JOIN mortality m
      ON dpc.subject_id = m.subject_id AND dpc.hadm_id = m.hadm_id
)

SELECT
  CASE WHEN hemorrhagic_stroke = 1 THEN 'Hemorrhagic Stroke' ELSE 'Other' END AS group_label,
  APPROX_QUANTILES(num_diagnostic_procedures, 100)[90] AS diagnostic_procedure_90th_percentile,
  APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_icu_los,
  ROUND(SUM(CAST(hospital_expire_flag AS INT64)) / COUNT(1), 4) AS in_hospital_mortality_rate
FROM
  final
GROUP BY
  hemorrhagic_stroke
ORDER BY
  hemorrhagic_stroke DESC;