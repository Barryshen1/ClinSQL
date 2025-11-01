WITH bleed_admissions AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.subject_id,
    p.gender,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_adm,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE di.seq_num = 1
    AND (
      dd.long_title LIKE '%hematemesis%'
      OR dd.long_title LIKE '%melena%'
      OR dd.long_title LIKE '%bleed%'
      OR dd.long_title LIKE '%hemorrhage%'
      OR dd.long_title LIKE '%gastric%'
      OR dd.long_title LIKE '%duodenal%'
      OR dd.long_title LIKE '%esophageal%'
      OR dd.long_title LIKE '%gastroduodenal%'
    )
    AND p.gender = 'M'
    -- age at admission exactly 70
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) = 70
)

SELECT
  quant[OFFSET(74)] AS p75_los_days
FROM (
  SELECT APPROX_QUANTILES(los_days, 100) AS quant
  FROM bleed_admissions
) q;