WITH cohort AS (
  SELECT
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    p.gender,
    p.anchor_age,
    ie.intime,
    ie.los,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
),
stroke_flags AS (
  SELECT
    hadm_id,
    MAX(
      CASE
        WHEN (icd_version = 9 AND (
              icd_code LIKE '430%' OR icd_code LIKE '431%' OR icd_code LIKE '432%'))
          OR (icd_version = 10 AND (
              icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I62%'))
        THEN 1 ELSE 0 END
    ) AS has_hemorrhagic_stroke
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
proc_in_72h AS (
  SELECT
    c.stay_id,
    COUNT(*) AS proc_count_72h
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON c.hadm_id = pr.hadm_id
  WHERE pr.chartdate >= DATE(c.intime)
    AND pr.chartdate <= DATE(DATETIME_ADD(c.intime, INTERVAL 72 HOUR))
  GROUP BY c.stay_id
),
cohort_with_flags AS (
  SELECT
    c.*,
    COALESCE(s.has_hemorrhagic_stroke, 0) AS has_hemorrhagic_stroke,
    COALESCE(p72.proc_count_72h, 0) AS proc_count_72h
  FROM cohort c
  LEFT JOIN stroke_flags s
    ON c.hadm_id = s.hadm_id
  LEFT JOIN proc_in_72h p72
    ON c.stay_id = p72.stay_id
)
SELECT
  CASE WHEN has_hemorrhagic_stroke = 1 THEN 'Hemorrhagic stroke' ELSE 'Other' END AS group_label,
  PERCENTILE_CONT(proc_count_72h, 0.9) OVER (PARTITION BY has_hemorrhagic_stroke) AS pct90_proc_72h,
  AVG(los) OVER (PARTITION BY has_hemorrhagic_stroke) AS avg_icu_los_days,
  100.0 * AVG(hospital_expire_flag) OVER (PARTITION BY has_hemorrhagic_stroke) AS mortality_rate_percent
FROM cohort_with_flags
GROUP BY has_hemorrhagic_stroke, proc_count_72h, los, hospital_expire_flag;