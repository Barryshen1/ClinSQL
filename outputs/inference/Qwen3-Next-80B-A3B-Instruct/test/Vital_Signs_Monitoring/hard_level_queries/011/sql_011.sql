WITH pneumonia_patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    p.gender,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON p.subject_id = d.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  JOIN physionet-data.mimiciv_3_1_icu.icustays i ON p.subject_id = i.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 55 AND 65
    AND LOWER(di.long_title) LIKE '%pneumonia%'
),
map_first_24h AS (
  SELECT
    pp.subject_id,
    pp.stay_id,
    AVG(ce.valuenum) AS mean_map_24h
  FROM pneumonia_patients pp
  JOIN physionet-data.mimiciv_3_1_icu.chartevents ce
    ON pp.stay_id = ce.stay_id
  JOIN physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  WHERE di.label = 'MAP'
    AND ce.charttime >= pp.intime
    AND ce.charttime < TIMESTAMP_ADD(pp.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY pp.subject_id, pp.stay_id
),
percentile_calc AS (
  SELECT
    mean_map_24h,
    CUME_DIST() OVER (ORDER BY mean_map_24h) AS percentile_rank
  FROM map_first_24h
)
SELECT
  (SELECT percentile_rank FROM percentile_calc WHERE mean_map_24h <= 60 ORDER BY mean_map_24h DESC LIMIT 1) AS percentile_of_60,
  AVG(pp.los) AS avg_los_most_unstable,
  AVG(CAST(pp.hospital_expire_flag AS FLOAT64)) AS mortality_rate_most_unstable
FROM map_first_24h m
JOIN pneumonia_patients pp ON m.stay_id = pp.stay_id
WHERE m.mean_map_24h <= (SELECT PERCENTILE_CONT(mean_map_24h, 0.1) OVER () FROM map_first_24h LIMIT 1);