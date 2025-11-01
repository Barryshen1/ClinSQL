WITH hf_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.discharge_location
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    -- age at admission
    AND 53 <= (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year))
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) <= 63
    -- HF diagnosis present for this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 9 AND di.icd_code LIKE '428%') -- ICD-9 HF
          OR (di.icd_version = 10 AND di.icd_code LIKE 'I50%') -- ICD-10 HF
        )
    )
),
los_mort AS (
  SELECT
    h.hadm_id,
    h.subject_id,
    h.admittime,
    h.dischtime,
    h.deathtime,
    h.hospital_expire_flag,
    h.discharge_location,
    TIMESTAMP_DIFF(h.dischtime, h.admittime, DAY) AS los_days,
    CASE
      WHEN UPPER(h.discharge_location) LIKE '%HOME%' THEN 'Home'
      WHEN UPPER(h.discharge_location) LIKE '%REHAB%' OR UPPER(h.discharge_location) LIKE '%REHABILIT%' THEN 'Rehab'
      WHEN UPPER(h.discharge_location) LIKE '%SNF%' OR UPPER(h.discharge_location) LIKE '%SKILLED%' THEN 'SNF'
      WHEN UPPER(h.discharge_location) LIKE '%HOSPICE%' THEN 'Hospice'
      ELSE 'Other'
    END AS discharge_cat
  FROM hf_cohort AS h
),
diag_flags AS (
  SELECT d.hadm_id,
         MAX(CASE
               WHEN (d.icd_version = 9 AND d.icd_code LIKE '410%') OR
                    (d.icd_version = 9 AND d.icd_code LIKE '411%') OR
                    (d.icd_version = 9 AND d.icd_code LIKE '412%') OR
                    (d.icd_version = 9 AND d.icd_code LIKE '413%') OR
                    (d.icd_version = 9 AND d.icd_code LIKE '414%')
                    THEN 1 ELSE 0 END) AS flag_MI,
         MAX(CASE WHEN (d.icd_version = 10 AND d.icd_code LIKE 'I21%') OR
                          (d.icd_version = 10 AND d.icd_code LIKE 'I22%')
                          THEN 1 ELSE 0 END) AS flag_MI10,
         MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code LIKE '428%') OR
                          (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
                          THEN 1 ELSE 0 END) AS flag_CHF,
         MAX(CASE WHEN (d.icd_version = 9 AND (d.icd_code LIKE '440%' OR d.icd_code LIKE '441%' OR d.icd_code LIKE '442%' OR d.icd_code LIKE '443%' OR d.icd_code LIKE '444%' OR d.icd_code LIKE '447%'))
                          OR (d.icd_version = 10 AND (d.icd_code LIKE 'I70%'))
                          THEN 1 ELSE 0 END) AS flag_PVD,
         MAX(CASE WHEN (d.icd_version = 9 AND (d.icd_code LIKE '430%') OR (d.icd_code LIKE '431%') OR (d.icd_code LIKE '432%') OR (d.icd_code LIKE '433%') OR (d.icd_code LIKE '434%'))
                          OR (d.icd_version = 10 AND (d.icd_code LIKE 'I60%') OR (d.icd_code LIKE 'I61%') OR (d.icd_code LIKE 'I62%') OR (d.icd_code LIKE 'I63%') OR (d.icd_code LIKE 'I64%'))
                          THEN 1 ELSE 0 END) AS flag_CV,
         MAX(CASE WHEN (d.icd_version = 9 AND (d.icd_code LIKE '290%' OR d.icd_code LIKE '291%' OR d.icd_code LIKE '292%' OR d.icd_code LIKE '293%' OR d.icd_code LIKE '294%'))
                          OR (d.icd_version = 10 AND (d.icd_code LIKE 'F02%' OR d.icd_code LIKE 'F03%'))
                          THEN 1 ELSE 0 END) AS flag_DEM,
         MAX(CASE WHEN (d.icd_version = 9 AND (d.icd_code LIKE '490%' OR d.icd_code LIKE '491%' OR d.icd_code LIKE '492%' OR d.icd_code LIKE '493%' OR d.icd_code LIKE '494%' OR d.icd_code LIKE '495%' OR d.icd_code LIKE '496%'))
                          OR (d.icd_version = 10 AND (d.icd_code LIKE 'J44%' OR d.icd_code LIKE 'J43%'))
                          THEN 1 ELSE 0 END) AS flag_COPD,
         MAX(CASE WHEN (d.icd_version = 9 AND (d.icd_code LIKE '710%' OR d.icd_code LIKE '711%' OR d.icd_code LIKE '712%' OR d.icd_code LIKE '713%'))
                          OR (d.icd_version = 10 AND (d.icd_code LIKE 'M35%' OR d.icd_code LIKE 'K64%'))
                          THEN 1 ELSE 0 END) AS flag_CTDS,
         MAX(CASE WHEN (d.icd_version = 9 AND (d.icd_code LIKE '531%' OR d.icd_code LIKE '532%' OR d.icd_code LIKE '533%' OR d.icd_code LIKE '534%'))
                          THEN 1 ELSE 0 END) AS flag_PUD,
         MAX(CASE WHEN (d.icd_version = 9 AND (d.icd_code LIKE '571%'))
                          OR (d.icd_version = 10 AND (d.icd_code LIKE 'K70%'))
                          THEN 1 ELSE 0 END) AS flag_LIVER,
         MAX(CASE WHEN (d.icd_version = 9 AND (d.icd_code LIKE '250%'))
                          OR (d.icd_version = 10 AND (d.icd_code LIKE 'E11%' OR d.icd_code LIKE '250%'))
                          THEN 1 ELSE 0 END) AS flag_DM,
         MAX(CASE WHEN (d.icd_version = 9 AND (d.icd_code LIKE '582%' OR d.icd_code LIKE '583%' OR d.icd_code LIKE '584%' OR d.icd_code LIKE '585%' OR d.icd_code LIKE '586%'))
                          OR (d.icd_version = 10 AND (d.icd_code LIKE 'N18%'))
                          THEN 1 ELSE 0 END) AS flag_RENAL,
         MAX(CASE WHEN (d.icd_version = 9 AND (d.icd_code LIKE '140%' OR d.icd_code LIKE '141%' OR d.icd_code LIKE '142%' OR d.icd_code LIKE '143%' OR d.icd_code LIKE '144%' OR d.icd_code LIKE '145%' OR d.icd_code LIKE '146%' OR d.icd_code LIKE '147%' OR d.icd_code LIKE '148%' OR d.icd_code LIKE '149%' OR d.icd_code LIKE '150%' OR d.icd_code LIKE '151%' OR d.icd_code LIKE '152%' OR d.icd_code LIKE '153%' OR d.icd_code LIKE '154%' OR d.icd_code LIKE '155%' OR d.icd_code LIKE '156%' OR d.icd_code LIKE '157%' OR d.icd_code LIKE '158%' OR d.icd_code LIKE '159%' OR d.icd_code LIKE '160%' OR d.icd_code LIKE '161%' OR d.icd_code LIKE '162%' OR d.icd_code LIKE '163%' OR d.icd_code LIKE '164%' OR d.icd_code LIKE '165%' OR d.icd_code LIKE '166%' OR d.icd_code LIKE '167%' OR d.icd_code LIKE '168%' OR d.icd_code LIKE '169%' OR d.icd_code LIKE '170%' OR d.icd_code LIKE '171%' OR d.icd_code LIKE '172%'))
                          OR (d.icd_version = 10 AND (d.icd_code LIKE 'C00%' OR d.icd_code LIKE 'C01%' OR d.icd_code LIKE 'C02%' OR d.icd_code LIKE 'C03%'))
                          THEN 1 ELSE 0 END) AS flag_SOLID,
         MAX(CASE WHEN (d.icd_version = 9 AND (d.icd_code LIKE '204%' OR d.icd_code LIKE '205%' OR d.icd_code LIKE '206%' OR d.icd_code LIKE '207%' OR d.icd_code LIKE '208%'))
                          OR (d.icd_version = 10 AND (d.icd_code LIKE 'C91%' OR d.icd_code LIKE 'C92%' OR d.icd_code LIKE 'C93%' OR d.icd_code LIKE 'C94%' OR d.icd_code LIKE 'C95%'))
                          THEN 1 ELSE 0 END) AS flag_LEUK
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE d.hadm_id IN (SELECT hadm_id FROM los_mort)
  GROUP BY d.hadm_id
),
comorb AS (
  SELECT
    l.hadm_id,
    -- sum of flags (Charlson proxy)
    COALESCE(f.flag_MI, 0) +
    COALESCE(f.flag_MI10, 0) +
    COALESCE(f.flag_CHF, 0) +
    COALESCE(f.flag_PVD, 0) +
    COALESCE(f.flag_CV, 0) +
    COALESCE(f.flag_DEM, 0) +
    COALESCE(f.flag_COPD, 0) +
    COALESCE(f.flag_CTDS, 0) +
    COALESCE(f.flag_PUD, 0) +
    COALESCE(f.flag_LIVER, 0) +
    COALESCE(f.flag_DM, 0) +
    COALESCE(f.flag_RENAL, 0) +
    COALESCE(f.flag_SOLID, 0) +
    COALESCE(f.flag_LEUK, 0)
    AS comorbidity_count
  FROM los_mort l
  LEFT JOIN diag_flags f ON f.hadm_id = l.hadm_id
),
cohort_combined AS (
  SELECT
    l.hadm_id,
    l.subject_id,
    l.admittime,
    l.dischtime,
    l.deathtime,
    l.hospital_expire_flag,
    l.discharge_cat,
    l.los_days,
    -- Charlson category from proxy
    CASE
      WHEN c.comorbidity_count IS NULL THEN 'Unknown'
      WHEN c.comorbidity_count <= 3 THEN '≤3'
      WHEN c.comorbidity_count BETWEEN 4 AND 5 THEN '4-5'
      ELSE '>5'
    END AS charlson_cat,
    CASE
      WHEN l.hospital_expire_flag = 1 OR l.deathtime IS NOT NULL THEN 1 ELSE 0
    END AS in_hosp_mort
  FROM los_mort l
  LEFT JOIN comorb c ON c.hadm_id = l.hadm_id
)
SELECT
  CASE
    WHEN los_days <= 3 THEN '1-3'
    WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
    WHEN los_days >= 8 THEN '≥8'
  END AS los_cat,
  charlson_cat,
  COUNT(*) AS n,
  SUM(in_hosp_mort) AS deaths,
  ROUND(100.0 * SUM(in_hosp_mort) / COUNT(*), 2) AS mortality_pct,
  AVG(los_days) AS mean_los_days
FROM cohort_combined
GROUP BY los_cat, charlson_cat
ORDER BY los_cat, charlson_cat;