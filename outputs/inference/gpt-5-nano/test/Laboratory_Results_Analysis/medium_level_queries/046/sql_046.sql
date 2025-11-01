WITH eligible_base AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_adm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE (LOWER(p.gender) = 'male' OR p.gender = 'M')
    AND p.anchor_age IS NOT NULL
    AND p.anchor_year IS NOT NULL
),
eligible_ami AS (
  SELECT DISTINCT eb.hadm_id
  FROM eligible_base AS eb
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON eb.hadm_id = di.hadm_id
   AND eb.subject_id = di.subject_id
  WHERE (di.icd_version = 9 AND di.icd_code LIKE '410%')
     OR (di.icd_version = 10 AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%'))
),
initial_troponin_all AS (
  SELECT le.hadm_id, le.valuenum AS troponin_value
  FROM (
    SELECT hadm_id, MIN(charttime) AS first_charttime
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
      ON le.itemid = dli.itemid
    WHERE LOWER(dli.label) LIKE '%troponin%t%'
    GROUP BY hadm_id
  ) AS t
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON le.hadm_id = t.hadm_id AND le.charttime = t.first_charttime
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE LOWER(dli.label) LIKE '%troponin%t%'
),
initial_troponin_eligible AS (
  SELECT itt.hadm_id, itt.troponin_value
  FROM initial_troponin_all AS itt
  JOIN eligible_ami AS ea ON itt.hadm_id = ea.hadm_id
),
final_cohort AS (
  SELECT ea.hadm_id,
         a.admittime,
         a.dischtime,
         (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_adm
  FROM eligible_ami AS ea
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON ea.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE ea.hadm_id IN (SELECT hadm_id FROM initial_troponin_eligible)
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 83 AND 93
),
troponin_stats AS (
  SELECT
    quantiles[OFFSET(25)] AS troponin_q1,
    quantiles[OFFSET(50)] AS troponin_median,
    quantiles[OFFSET(75)] AS troponin_q3
  FROM (
     SELECT APPROX_QUANTILES(it.troponin_value, 100) AS quantiles
     FROM initial_troponin_eligible AS it
  ) AS q
)

SELECT
  COUNT(DISTINCT fc.hadm_id) AS N,
  AVG(fc.age_at_adm) AS mean_age_at_adm,
  AVG(TIMESTAMP_DIFF(fc.dischtime, fc.admittime, SECOND) / 86400.0) AS mean_los_days,
  AVG(it.troponin_value) AS mean_initial_troponin,
  MIN(it.troponin_value) AS min_initial_troponin,
  MAX(it.troponin_value) AS max_initial_troponin,
  MAX(ts.troponin_q1) AS troponin_q1,
  MAX(ts.troponin_median) AS troponin_median,
  MAX(ts.troponin_q3) AS troponin_q3
FROM final_cohort fc
JOIN initial_troponin_eligible AS it ON fc.hadm_id = it.hadm_id
CROSS JOIN troponin_stats ts;