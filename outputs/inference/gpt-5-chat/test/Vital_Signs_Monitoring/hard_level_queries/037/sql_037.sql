WITH hf_patients AS (
  SELECT DISTINCT icu.subject_id, icu.hadm_id, icu.stay_id,
                  icu.intime, icu.los,
                  pat.gender, pat.anchor_age,
                  adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON icu.hadm_id = dx.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON dx.icd_code = d.icd_code AND dx.icd_version = d.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 45 AND 55
    AND (
      (dx.icd_version = 9 AND dx.icd_code LIKE '428%')
      OR (dx.icd_version = 10 AND dx.icd_code LIKE 'I50%')
    )
),
vitals72h AS (
  SELECT ce.subject_id, ce.hadm_id, ce.stay_id,
         CASE WHEN ce.itemid IN (220045, 211) AND ce.valuenum > 100 THEN 1 ELSE 0 END AS tachycardia,
         CASE WHEN ce.itemid IN (220052, 220181, 456) AND ce.valuenum < 65 THEN 1 ELSE 0 END AS map_low,
         CASE WHEN ce.itemid IN (220210, 615) AND ce.valuenum > 20 THEN 1 ELSE 0 END AS tachypnea
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN hf_patients hp
    ON ce.subject_id = hp.subject_id AND ce.stay_id = hp.stay_id
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime >= hp.intime
    AND ce.charttime < DATETIME_ADD(hp.intime, INTERVAL 72 HOUR)
),
score_per_stay AS (
  SELECT subject_id, hadm_id, stay_id,
         SUM(tachycardia + map_low + tachypnea) AS composite_score,
         AVG(tachycardia) AS pct_tachy,
         AVG(map_low) AS pct_map_low,
         AVG(tachypnea) AS pct_tachypnea
  FROM vitals72h
  GROUP BY subject_id, hadm_id, stay_id
),
with_stats AS (
  SELECT s.*, hp.los, hp.hospital_expire_flag
  FROM score_per_stay s
  JOIN hf_patients hp
    ON s.subject_id = hp.subject_id AND s.stay_id = hp.stay_id
),
percentiles AS (
  SELECT APPROX_QUANTILES(composite_score, 100)[OFFSET(99)] AS p99,
         APPROX_QUANTILES(composite_score, 4) AS quartiles
  FROM with_stats
),
classified AS (
  SELECT w.*,
         p.p99,
         CASE WHEN composite_score >= p.quartiles[OFFSET(3)] THEN 'most_unstable' ELSE 'other' END AS quartile_group
  FROM with_stats w
  CROSS JOIN percentiles p
)
SELECT quartile_group,
       AVG(pct_tachy) AS avg_prop_tachycardia,
       AVG(pct_map_low) AS avg_prop_map_lt65,
       AVG(pct_tachypnea) AS avg_prop_tachypnea,
       AVG(los) AS avg_icu_los_days,
       AVG(hospital_expire_flag) AS mortality_rate
FROM classified
GROUP BY quartile_group;