WITH hadm_stroke AS (
  SELECT dx.hadm_id,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%stroke%' THEN 1 ELSE 0 END) AS has_stroke
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON dx.icd_code = dd.icd_code AND dx.icd_version = dd.icd_version
  GROUP BY dx.hadm_id
),
rr_per_stay AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    AVG(ce.valuenum) AS per_stay_avg_rr
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.subject_id = i.subject_id
   AND ce.hadm_id = i.hadm_id
   AND ce.stay_id = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE LOWER(di.label) LIKE '%respiratory rate%'
    AND ce.charttime >= i.intime
    AND ce.charttime < TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
    AND p.gender = 'Female'
    AND p.anchor_age BETWEEN 41 AND 51
  GROUP BY i.subject_id, i.hadm_id, i.stay_id
)
SELECT
  CASE
     WHEN per_stay_avg_rr < 12 THEN '<12'
     WHEN per_stay_avg_rr >= 12 AND per_stay_avg_rr <= 20 THEN '12-20'
     WHEN per_stay_avg_rr >= 21 AND per_stay_avg_rr <= 29 THEN '21-29'
     WHEN per_stay_avg_rr >= 30 THEN '30+'
  END AS rr_bin,
  COUNT(*) AS n_patients,
  SUM(COALESCE(hs.has_stroke, 0)) AS stroke_count,
  ROUND(SAFE_DIVIDE(SUM(COALESCE(hs.has_stroke, 0)), COUNT(*)) * 100, 2) AS stroke_rate_percent
FROM rr_per_stay rs
LEFT JOIN hadm_stroke hs
  ON rs.hadm_id = hs.hadm_id
GROUP BY rr_bin
ORDER BY rr_bin;