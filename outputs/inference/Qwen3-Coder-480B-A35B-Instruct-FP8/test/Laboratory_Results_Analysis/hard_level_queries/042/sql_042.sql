WITH ich_cohort AS (
  SELECT DISTINCT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.los,
    adm.hospital_expire_flag
  FROM
    physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions adm
    ON icu.hadm_id = adm.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients pat
    ON icu.subject_id = pat.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd dx
    ON icu.hadm_id = dx.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_dx
    ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 73 AND 83
    AND LOWER(d_dx.long_title) LIKE '%intracranial hemorrhage%'
),

lab_scores AS (
  SELECT
    ich.stay_id,
    COUNT(DISTINCT CASE WHEN lab.flag = 'abnormal' THEN lab.itemid END) AS instability_score
  FROM
    ich_cohort ich
  JOIN
    physionet-data.mimiciv_3_1_hosp.labevents lab
    ON ich.hadm_id = lab.hadm_id
  WHERE
    lab.flag IS NOT NULL
    AND lab.charttime >= (
      SELECT intime
      FROM physionet-data.mimiciv_3_1_icu.icustays icu2
      WHERE icu2.stay_id = ich.stay_id
    )
    AND lab.charttime <= DATETIME_ADD(
      (
        SELECT intime
        FROM physionet-data.mimiciv_3_1_icu.icustays icu2
        WHERE icu2.stay_id = ich.stay_id
      ),
      INTERVAL 48 HOUR
    )
  GROUP BY
    ich.stay_id
),

quartiles AS (
  SELECT
    stay_id,
    instability_score,
    NTILE(4) OVER (ORDER BY instability_score) AS quartile
  FROM
    lab_scores
),

metrics_per_quartile AS (
  SELECT
    q.quartile,
    COUNT(*) AS patient_count,
    AVG(ich.los) AS mean_los,
    AVG(ich.hospital_expire_flag) AS mortality_rate
  FROM
    quartiles q
  JOIN
    ich_cohort ich
    ON q.stay_id = ich.stay_id
  GROUP BY
    q.quartile
),

all_icu_metrics AS (
  SELECT
    COUNT(*) AS total_patients,
    AVG(los) AS avg_los,
    AVG(hospital_expire_flag) AS overall_mortality
  FROM
    physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions adm
    ON icu.hadm_id = adm.hadm_id
)

SELECT
  m.quartile,
  m.patient_count,
  m.mean_los,
  m.mortality_rate,
  a.avg_los AS all_icu_mean_los,
  a.overall_mortality AS all_icu_mortality
FROM
  metrics_per_quartile m
CROSS JOIN
  all_icu_metrics a
ORDER BY
  m.quartile;