WITH base_cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
icu_flagged AS (
  SELECT
    b.*,
    CASE WHEN icu.subject_id IS NOT NULL THEN 1 ELSE 0 END AS icu_flag
  FROM base_cohort b
  LEFT JOIN (
    SELECT DISTINCT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) icu
    ON b.subject_id = icu.subject_id
   AND b.hadm_id = icu.hadm_id
),
los_categorized AS (
  SELECT
    *,
    CASE WHEN DATE_DIFF(dischtime, admittime, DAY) <= 5 THEN '≤5 days' ELSE '>5 days' END AS los_cat
  FROM icu_flagged
),
comorbidity_count AS (
  SELECT
    lc.subject_id,
    lc.hadm_id,
    lc.gender,
    lc.anchor_age,
    lc.admittime,
    lc.dischtime,
    lc.hospital_expire_flag,
    lc.icu_flag,
    lc.los_cat,
    COUNT(DISTINCT d.icd_code) AS comorb_count
  FROM los_categorized lc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON lc.subject_id = d.subject_id
   AND lc.hadm_id = d.hadm_id
  GROUP BY lc.subject_id, lc.hadm_id, lc.gender, lc.anchor_age,
           lc.admittime, lc.dischtime, lc.hospital_expire_flag,
           lc.icu_flag, lc.los_cat
),
tertiles AS (
  SELECT
    *,
    NTILE(3) OVER (ORDER BY comorb_count) AS comorb_tertile
  FROM comorbidity_count
),
dx_flags AS (
  SELECT
    t.*,
    -- Flag CKD per ICD-9/10 pattern in diagnosis text
    MAX( CASE
          WHEN (dl.icd_version = 9 AND dl.icd_code LIKE '585%')
            OR (dl.icd_version = 10 AND dl.icd_code LIKE 'N18%')
          THEN 1 ELSE 0 END
        ) AS ckdpresent,
    MAX( CASE
          WHEN (dl.icd_version = 9 AND dl.icd_code LIKE '250%')
            OR (dl.icd_version = 10 AND dl.icd_code LIKE 'E1%' AND SUBSTR(dl.icd_code,1,3) IN ('E10','E11','E12','E13','E14'))
          THEN 1 ELSE 0 END
        ) AS diabpresent
  FROM tertiles t
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dl
    ON t.subject_id = dl.subject_id
   AND t.hadm_id = dl.hadm_id
  GROUP BY t.subject_id, t.hadm_id, t.gender, t.anchor_age, t.admittime,
           t.dischtime, t.hospital_expire_flag, t.icu_flag, t.los_cat,
           t.comorb_count, t.comorb_tertile
)
SELECT
  icu_flag,
  los_cat,
  comorb_tertile,
  COUNT(*) AS n_admissions,
  ROUND(AVG(hospital_expire_flag)*100,2) AS mortality_pct,
  ROUND(AVG(ckdpresent)*100,2) AS ckd_pct,
  ROUND(AVG(diabpresent)*100,2) AS diabetes_pct
FROM dx_flags
GROUP BY icu_flag, los_cat, comorb_tertile
ORDER BY icu_flag, los_cat, comorb_tertile;