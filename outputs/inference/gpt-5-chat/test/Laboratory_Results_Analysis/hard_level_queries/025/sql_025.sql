WITH hemorrhage_dx AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.subject_id = dx.subject_id
   AND adm.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON dx.icd_code = dd.icd_code
   AND dx.icd_version = dd.icd_version
  WHERE (
    (dx.icd_version = 9 AND (dx.icd_code LIKE '430%' OR dx.icd_code LIKE '431%' OR dx.icd_code LIKE '432%'))
    OR (dx.icd_version = 10 AND (dx.icd_code LIKE 'I60%' OR dx.icd_code LIKE 'I61%' OR dx.icd_code LIKE 'I62%'))
  )
),
target_cases AS (
  SELECT adm.subject_id, adm.hadm_id, pat.gender, pat.anchor_age, adm.admittime, adm.dischtime, adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN hemorrhage_dx hdx
    ON adm.subject_id = hdx.subject_id
   AND adm.hadm_id = hdx.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 48 AND 58
),
age_matched_cohort AS (
  SELECT adm.subject_id, adm.hadm_id, pat.gender, pat.anchor_age, adm.admittime, adm.dischtime, adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 48 AND 58
    AND NOT EXISTS (
      SELECT 1
      FROM hemorrhage_dx hdx
      WHERE hdx.subject_id = adm.subject_id
        AND hdx.hadm_id = adm.hadm_id
    )
),
labs_first72h AS (
  SELECT l.subject_id, l.hadm_id, l.itemid
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON l.subject_id = adm.subject_id
   AND l.hadm_id = adm.hadm_id
  WHERE l.charttime BETWEEN adm.admittime AND TIMESTAMP_ADD(adm.admittime, INTERVAL 72 HOUR)
    AND (
      LOWER(l.flag) LIKE '%abnormal%'
      OR LOWER(l.flag) LIKE '%critical%'
      OR (l.valuenum IS NOT NULL AND l.ref_range_lower IS NOT NULL AND l.valuenum < l.ref_range_lower)
      OR (l.valuenum IS NOT NULL AND l.ref_range_upper IS NOT NULL AND l.valuenum > l.ref_range_upper)
    )
  GROUP BY l.subject_id, l.hadm_id, l.itemid
),
scores_cases AS (
  SELECT tc.subject_id, tc.hadm_id, COUNT(DISTINCT lf.itemid) AS lab_instability_score,
         tc.hospital_expire_flag,
         TIMESTAMP_DIFF(tc.dischtime, tc.admittime, DAY) AS los_days
  FROM target_cases tc
  LEFT JOIN labs_first72h lf
    ON tc.subject_id = lf.subject_id AND tc.hadm_id = lf.hadm_id
  GROUP BY tc.subject_id, tc.hadm_id, tc.hospital_expire_flag, tc.admittime, tc.dischtime
),
scores_cohort AS (
  SELECT ac.subject_id, ac.hadm_id, COUNT(DISTINCT lf.itemid) AS lab_instability_score,
         ac.hospital_expire_flag,
         TIMESTAMP_DIFF(ac.dischtime, ac.admittime, DAY) AS los_days
  FROM age_matched_cohort ac
  LEFT JOIN labs_first72h lf
    ON ac.subject_id = lf.subject_id AND ac.hadm_id = lf.hadm_id
  GROUP BY ac.subject_id, ac.hadm_id, ac.hospital_expire_flag, ac.admittime, ac.dischtime
),
p90_val AS (
  SELECT APPROX_QUANTILES(lab_instability_score, 100)[OFFSET(90)] AS p90_score
  FROM scores_cases
),
group_a AS (
  SELECT 'Cases≥P90' AS group_label,
         COUNT(*) AS n_patients,
         100*AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_percent,
         AVG(los_days) AS mean_los_days,
         AVG(lab_instability_score) AS avg_critical_labs
  FROM scores_cases, p90_val
  WHERE lab_instability_score >= p90_score
),
group_b AS (
  SELECT 'Age-matched cohort' AS group_label,
         COUNT(*) AS n_patients,
         100*AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_percent,
         AVG(los_days) AS mean_los_days,
         AVG(lab_instability_score) AS avg_critical_labs
  FROM scores_cohort
)
SELECT * FROM group_a
UNION ALL
SELECT * FROM group_b;