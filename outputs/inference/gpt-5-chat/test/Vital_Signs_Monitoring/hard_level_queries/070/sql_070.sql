WITH hhs_admissions AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%hyperosmolar%'
),
male_elderly AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 78 AND 88
),
vital_itemids AS (
  SELECT 
    MAX(CASE WHEN LOWER(label) = 'heart rate' THEN itemid END) AS hr_itemid,
    MAX(CASE WHEN LOWER(label) = 'mean arterial pressure' THEN itemid END) AS map_itemid,
    MAX(CASE WHEN LOWER(label) = 'respiratory rate' THEN itemid END) AS rr_itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) IN ('heart rate','mean arterial pressure','respiratory rate')
),
first24h_vitals AS (
  SELECT ce.stay_id,
         ce.itemid,
         ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.stay_id = icu.stay_id
  JOIN male_elderly me ON icu.subject_id = me.subject_id
  JOIN hhs_admissions ha ON icu.hadm_id = ha.hadm_id
                        AND icu.subject_id = ha.subject_id
  CROSS JOIN vital_itemids vi
  WHERE ce.valuenum IS NOT NULL
    AND ce.itemid IN (vi.hr_itemid, vi.map_itemid, vi.rr_itemid)
    AND ce.charttime BETWEEN icu.intime
                         AND DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
),
cv_per_stay AS (
  SELECT
    stay_id,
    STDDEV(IF(itemid = hr_itemid, valuenum, NULL)) / AVG(IF(itemid = hr_itemid, valuenum, NULL)) AS cv_hr,
    STDDEV(IF(itemid = map_itemid, valuenum, NULL)) / AVG(IF(itemid = map_itemid, valuenum, NULL)) AS cv_map,
    STDDEV(IF(itemid = rr_itemid, valuenum, NULL)) / AVG(IF(itemid = rr_itemid, valuenum, NULL)) AS cv_rr,
    SUM(
      CASE 
        WHEN itemid = hr_itemid AND (valuenum < 60 OR valuenum > 100) THEN 1
        WHEN itemid = map_itemid AND (valuenum < 70 OR valuenum > 105) THEN 1
        WHEN itemid = rr_itemid AND (valuenum < 12 OR valuenum > 20) THEN 1
        ELSE 0
      END
    ) AS abnormal_vital_count
  FROM first24h_vitals f
  CROSS JOIN vital_itemids vi
  GROUP BY stay_id
),
cv_summary AS (
  SELECT
    stay_id,
    (cv_hr + cv_map + cv_rr) AS instability_score,
    abnormal_vital_count
  FROM cv_per_stay
),
quartile_cut AS (
  SELECT APPROX_QUANTILES(instability_score, 4)[OFFSET(3)] AS q3
  FROM cv_summary
),
scored AS (
  SELECT
    s.stay_id,
    s.instability_score,
    NTILE(10) OVER (ORDER BY s.instability_score) AS decile,
    s.abnormal_vital_count,
    icu.los AS icu_los,
    adm.hospital_expire_flag
  FROM cv_summary s
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON s.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  WHERE s.instability_score >= (SELECT q3 FROM quartile_cut)
)
SELECT stay_id,
       instability_score,
       decile,
       abnormal_vital_count,
       icu_los,
       hospital_expire_flag
FROM scored
ORDER BY instability_score DESC;