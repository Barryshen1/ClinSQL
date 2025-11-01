WITH hhs_admissions AS (
  SELECT DISTINCT
    di.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    REGEXP_CONTAINS(d.icd_code, r'^(250\.2|E13\.00|E14\.00)$')
),

eligible_patients AS (
  SELECT
    p.subject_id
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
),

eligible_icu_stays AS (
  SELECT
    icu.stay_id,
    icu.hadm_id,
    icu.intime,
    icu.outtime,
    icu.los AS icu_los,
    adm.hospital_expire_flag
  FROM
    physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions adm
    ON icu.hadm_id = adm.hadm_id
  JOIN
    eligible_patients ep
    ON icu.subject_id = ep.subject_id
  JOIN
    hhs_admissions hhs
    ON icu.hadm_id = hhs.hadm_id
),

vitals_map AS (
  SELECT
    itemid,
    CASE
      WHEN LOWER(label) LIKE '%heart rate%' THEN 'HR'
      WHEN LOWER(label) LIKE '%mean blood pressure%' OR LOWER(label) LIKE '%map%' THEN 'MAP'
      WHEN LOWER(label) LIKE '%respiratory rate%' THEN 'RR'
    END AS vital_type
  FROM
    physionet-data.mimiciv_3_1_icu.d_items
  WHERE
    LOWER(label) IN ('heart rate', 'respiratory rate', 'arterial blood pressure mean', 'map')
),

vitals_data AS (
  SELECT
    ce.stay_id,
    vm.vital_type,
    ce.valuenum,
    ce.charttime
  FROM
    physionet-data.mimiciv_3_1_icu.chartevents ce
  JOIN
    vitals_map vm
    ON ce.itemid = vm.itemid
  JOIN
    eligible_icu_stays eis
    ON ce.stay_id = eis.stay_id
  WHERE
    ce.valuenum IS NOT NULL
    AND ce.charttime >= eis.intime
    AND ce.charttime <= DATETIME_ADD(eis.intime, INTERVAL 24 HOUR)
),

vitals_stats AS (
  SELECT
    stay_id,
    vital_type,
    AVG(valuenum) AS mean_val,
    STDDEV(valuenum) AS stddev_val
  FROM
    vitals_data
  GROUP BY
    stay_id, vital_type
),

cv_per_vital AS (
  SELECT
    stay_id,
    vital_type,
    CASE WHEN mean_val > 0 THEN stddev_val / mean_val ELSE NULL END AS cv
  FROM
    vitals_stats
),

cv_sum AS (
  SELECT
    stay_id,
    SUM(cv) AS cv_sum
  FROM
    cv_per_vital
  WHERE
    cv IS NOT NULL
  GROUP BY
    stay_id
),

abnormal_vitals AS (
  SELECT
    stay_id,
    COUNT(*) AS abnormal_count
  FROM
    vitals_data
  WHERE
    (vital_type = 'HR' AND (valuenum < 50 OR valuenum > 130))
    OR (vital_type = 'MAP' AND (valuenum < 60 OR valuenum > 120))
    OR (vital_type = 'RR' AND (valuenum < 10 OR valuenum > 25))
  GROUP BY
    stay_id
),

instability_scores AS (
  SELECT
    eis.stay_id,
    COALESCE(av.abnormal_count, 0) AS abnormal_vital_count,
    eis.icu_los,
    eis.hospital_expire_flag
  FROM
    eligible_icu_stays eis
  LEFT JOIN
    abnormal_vitals av
    ON eis.stay_id = av.stay_id
),

combined_scores AS (
  SELECT
    i.stay_id,
    i.abnormal_vital_count,
    i.icu_los,
    i.hospital_expire_flag,
    c.cv_sum
  FROM
    instability_scores i
  JOIN
    cv_sum c
    ON i.stay_id = c.stay_id
),

top_quartile AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY cv_sum DESC) AS quartile
  FROM
    combined_scores
),

filtered_top AS (
  SELECT *
  FROM top_quartile
  WHERE quartile = 1
),

final_with_deciles AS (
  SELECT
    stay_id,
    abnormal_vital_count AS instability_score,
    NTILE(10) OVER (ORDER BY abnormal_vital_count) AS decile,
    abnormal_vital_count,
    icu_los,
    hospital_expire_flag
  FROM
    filtered_top
)

SELECT
  stay_id,
  instability_score,
  decile,
  abnormal_vital_count,
  icu_los,
  hospital_expire_flag
FROM
  final_with_deciles
ORDER BY
  instability_score DESC;