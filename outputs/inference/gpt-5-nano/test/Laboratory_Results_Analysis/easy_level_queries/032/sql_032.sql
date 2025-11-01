WITH COPD_subjects AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON p.subject_id = di.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    -- approximate 90-year-old: age around 90
    AND p.anchor_age BETWEEN 89 AND 91
    -- COPD codes: ICD-9 491x, 492x, 496; ICD-10 J44*
    AND (
          (di.icd_version = 9 AND (di.icd_code LIKE '491%' OR di.icd_code LIKE '492%' OR di.icd_code LIKE '496%'))
          OR
          (di.icd_version = 10 AND di.icd_code LIKE 'J44%')
        )
),

-- 2) Compute per-ICU-stay mean serum creatinine in first 24 hours
First24hr_creatinine AS (
  SELECT
    i.hadm_id,
    i.subject_id,
    AVG(l.valuenum) AS mean_creatinine_first24
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
    ON l.hadm_id = i.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON l.itemid = dli.itemid
  WHERE i.subject_id IN (SELECT subject_id FROM COPD_subjects)
    -- serum creatinine measurements
    AND LOWER(dli.label) LIKE '%creatinin%'
    AND LOWER(dli.fluid) LIKE '%serum%'
    -- first 24 hours window from ICU intime
    AND l.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
  GROUP BY i.hadm_id, i.subject_id
)

-- 3) Standard deviation across per-stay means
SELECT
  STDDEV_SAMP(mean_creatinine_first24) AS sd_serum_creatinine_first24h
FROM First24hr_creatinine;