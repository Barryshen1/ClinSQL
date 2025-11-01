WITH ich_cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    pat.anchor_age,
    adm.admittime,
    COALESCE(adm.deathtime, pat.dod) AS death_datetime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.subject_id = dx.subject_id AND adm.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dxd
    ON dx.icd_code = dxd.icd_code AND dx.icd_version = dxd.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 68 AND 78
    AND (
      LOWER(dxd.long_title) LIKE '%intracerebral hemorrhage%'
      OR LOWER(dxd.long_title) LIKE '%intracranial hemorrhage%'
    )
    AND EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
      WHERE icu.subject_id = adm.subject_id
        AND icu.hadm_id = adm.hadm_id
    )
),
flags AS (
  SELECT
    c.*,
    CASE
      WHEN death_datetime IS NOT NULL
       AND DATE_DIFF(DATE(death_datetime), DATE(admittime), DAY) <= 30
      THEN 1 ELSE 0
    END AS died30_flag,
    CASE
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dxd
          ON dx.icd_code = dxd.icd_code AND dx.icd_version = dxd.icd_version
        WHERE dx.subject_id = c.subject_id AND dx.hadm_id = c.hadm_id
          AND (
            (dx.icd_version = 9 AND dx.icd_code LIKE '584%')
            OR (dx.icd_version = 10 AND dx.icd_code LIKE 'N17%')
          )
      ) THEN 1 ELSE 0
    END AS aki_flag,
    CASE
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dxd
          ON dx.icd_code = dxd.icd_code AND dx.icd_version = dxd.icd_version
        WHERE dx.subject_id = c.subject_id AND dx.hadm_id = c.hadm_id
          AND (
            (dx.icd_version = 9 AND (dx.icd_code = '51882' OR dx.icd_code = '5185'))
            OR (dx.icd_version = 10 AND dx.icd_code = 'J80')
          )
      ) THEN 1 ELSE 0
    END AS ards_flag,
    CASE WHEN death_datetime IS NOT NULL
      THEN DATE_DIFF(DATE(death_datetime), DATE(admittime), DAY)
    END AS days_survive
  FROM ich_cohort c
),
scored AS (
  SELECT
    *,
    (aki_flag + ards_flag + died30_flag) AS composite_score
  FROM flags
)
SELECT
  COUNT(*) AS cohort_size,
  ROUND(100 * AVG(died30_flag), 1) AS mortality_30day_rate_pct,
  ROUND(100 * AVG(aki_flag), 1) AS aki_rate_pct,
  ROUND(100 * AVG(ards_flag), 1) AS ards_rate_pct,
  approx_quantiles(composite_score, 4)[OFFSET(1)] AS composite_p25,
  approx_quantiles(composite_score, 4)[OFFSET(2)] AS composite_p50,
  approx_quantiles(composite_score, 4)[OFFSET(3)] AS composite_p75,
  approx_quantiles(days_survive, 2 IGNORE NULLS)[OFFSET(1)] AS median_survival_days_decedents
FROM scored;