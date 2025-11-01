WITH amipatients AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.dod,
    i.stay_id
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_icu.icustays i
    ON a.hadm_id = i.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did
    ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '410%')
      OR (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
    )
),

baseline_creatinine AS (
  SELECT
    ap.subject_id,
    ap.hadm_id,
    MIN(le.valuenum) AS baseline_creatinine
  FROM amipatients ap
  INNER JOIN physionet-data.mimiciv_3_1_hosp.labevents le
    ON ap.subject_id = le.subject_id AND ap.hadm_id = le.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl
    ON le.itemid = dl.itemid
  WHERE dl.label = 'Creatinine'
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0
    AND le.charttime >= ap.admittime
    AND le.charttime <= TIMESTAMP_ADD(ap.admittime, INTERVAL 24 HOUR)
  GROUP BY ap.subject_id, ap.hadm_id
),

aki_flag AS (
  SELECT
    ap.subject_id,
    ap.hadm_id,
    MAX(
      CASE
        WHEN le.valuenum >= (bc.baseline_creatinine * 1.5)
          OR (le.valuenum - bc.baseline_creatinine) >= 0.3
        THEN 1
        ELSE 0
      END
    ) AS has_aki
  FROM amipatients ap
  INNER JOIN physionet-data.mimiciv_3_1_hosp.labevents le
    ON ap.subject_id = le.subject_id AND ap.hadm_id = le.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl
    ON le.itemid = dl.itemid
  INNER JOIN baseline_creatinine bc
    ON ap.subject_id = bc.subject_id AND ap.hadm_id = bc.hadm_id
  WHERE dl.label = 'Creatinine'
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0
    AND le.charttime >= ap.admittime
    AND le.charttime <= TIMESTAMP_ADD(ap.admittime, INTERVAL 7 DAY)
  GROUP BY ap.subject_id, ap.hadm_id
),

ards_flag AS (
  SELECT DISTINCT
    ap.subject_id,
    ap.hadm_id,
    1 AS has_ards
  FROM amipatients ap
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON ap.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did
    ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE (d.icd_version = 9 AND d.icd_code = '518.82')
     OR (d.icd_version = 10 AND d.icd_code = 'J80')
)

SELECT
  COUNTIF(ap.dod IS NOT NULL AND CAST(ap.dod AS TIMESTAMP) <= TIMESTAMP_ADD(ap.dischtime, INTERVAL 30 DAY)) * 1.0 / COUNT(*) AS thirty_day_mortality_rate,
  COUNTIF(aki.has_aki = 1) * 1.0 / COUNT(*) AS aki_rate,
  COUNTIF(ards.has_ards = 1) * 1.0 / COUNT(*) AS ards_rate,
  PERCENTILE_CONT(CASE 
    WHEN ap.dod IS NOT NULL AND CAST(ap.dod AS TIMESTAMP) <= TIMESTAMP_ADD(ap.dischtime, INTERVAL 30 DAY) 
    THEN TIMESTAMP_DIFF(CAST(ap.dod AS TIMESTAMP), ap.dischtime, DAY) 
  END, 0.5) AS median_survival_days_decedents
FROM amipatients ap
LEFT JOIN aki_flag aki ON ap.subject_id = aki.subject_id AND ap.hadm_id = aki.hadm_id
LEFT JOIN ards_flag ards ON ap.subject_id = ards.subject_id AND ap.hadm_id = ards.hadm_id;