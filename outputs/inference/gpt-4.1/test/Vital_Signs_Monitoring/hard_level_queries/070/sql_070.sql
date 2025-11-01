WITH
-- 1. Get itemids for HR, MAP, RR
vital_itemids AS (
  SELECT
    MAX(CASE WHEN LOWER(label) LIKE '%heart rate%' THEN itemid END) AS hr_itemid,
    MAX(CASE WHEN LOWER(label) LIKE '%mean arterial%' THEN itemid END) AS map_itemid,
    MAX(CASE WHEN LOWER(label) LIKE '%respiratory rate%' THEN itemid END) AS rr_itemid
  FROM physionet-data.mimiciv_3_1_icu.d_items
  WHERE LOWER(label) LIKE '%heart rate%'
     OR LOWER(label) LIKE '%mean arterial%'
     OR LOWER(label) LIKE '%respiratory rate%'
),
-- 2. Cohort: male ICU patients aged 78-88 with HHS
hhs_stays AS (
  SELECT
    icu.stay_id,
    icu.hadm_id,
    icu.subject_id,
    icu.intime,
    icu.outtime,
    icu.los
  FROM physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN physionet-data.mimiciv_3_1_hosp.patients pat
    ON icu.subject_id = pat.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd diag
    ON icu.hadm_id = diag.hadm_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 78 AND 88
    AND (
      -- HHS ICD-10 codes (E11.0x, E11.1x, E11.6x, E11.9x, E13.0x, E13.1x, E13.6x, E13.9x, E08.0x, E08.1x, E08.6x, E08.9x, E09.0x, E09.1x, E09.6x, E09.9x, E10.0x, E10.1x, E10.6x, E10.9x, E12.0x, E12.1x, E12.6x, E12.9x, E14.0x, E14.1x, E14.6x, E14.9x)
      diag.icd_code LIKE 'E11.0%' OR diag.icd_code LIKE 'E11.1%' OR diag.icd_code LIKE 'E11.6%' OR diag.icd_code LIKE 'E11.9%'
      OR diag.icd_code LIKE 'E13.0%' OR diag.icd_code LIKE 'E13.1%' OR diag.icd_code LIKE 'E13.6%' OR diag.icd_code LIKE 'E13.9%'
      OR diag.icd_code LIKE 'E08.0%' OR diag.icd_code LIKE 'E08.1%' OR diag.icd_code LIKE 'E08.6%' OR diag.icd_code LIKE 'E08.9%'
      OR diag.icd_code LIKE 'E09.0%' OR diag.icd_code LIKE 'E09.1%' OR diag.icd_code LIKE 'E09.6%' OR diag.icd_code LIKE 'E09.9%'
      OR diag.icd_code LIKE 'E10.0%' OR diag.icd_code LIKE 'E10.1%' OR diag.icd_code LIKE 'E10.6%' OR diag.icd_code LIKE 'E10.9%'
      OR diag.icd_code LIKE 'E12.0%' OR diag.icd_code LIKE 'E12.1%' OR diag.icd_code LIKE 'E12.6%' OR diag.icd_code LIKE 'E12.9%'
      OR diag.icd_code LIKE 'E14.0%' OR diag.icd_code LIKE 'E14.1%' OR diag.icd_code LIKE 'E14.6%' OR diag.icd_code LIKE 'E14.9%'
    )
),
-- 3. Get 24h vital measurements for each stay
vitals_24h AS (
  SELECT
    v.stay_id,
    v.itemid,
    v.valuenum
  FROM physionet-data.mimiciv_3_1_icu.chartevents v
  JOIN hhs_stays s
    ON v.stay_id = s.stay_id
  JOIN vital_itemids vi
    ON v.itemid IN (vi.hr_itemid, vi.map_itemid, vi.rr_itemid)
  WHERE v.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
    AND v.valuenum IS NOT NULL
),
-- 4. Calculate CVs and abnormal counts per stay
vital_stats AS (
  SELECT
    s.stay_id,
    -- HR stats
    SAFE_DIVIDE(STDDEV(IF(v.itemid = vi.hr_itemid, v.valuenum, NULL)), AVG(IF(v.itemid = vi.hr_itemid, v.valuenum, NULL))) AS cv_hr,
    COUNTIF(v.itemid = vi.hr_itemid) AS n_hr,
    COUNTIF(v.itemid = vi.hr_itemid AND (v.valuenum < 50 OR v.valuenum > 120)) > 0 AS abnormal_hr,
    -- MAP stats
    SAFE_DIVIDE(STDDEV(IF(v.itemid = vi.map_itemid, v.valuenum, NULL)), AVG(IF(v.itemid = vi.map_itemid, v.valuenum, NULL))) AS cv_map,
    COUNTIF(v.itemid = vi.map_itemid) AS n_map,
    COUNTIF(v.itemid = vi.map_itemid AND (v.valuenum < 65 OR v.valuenum > 110)) > 0 AS abnormal_map,
    -- RR stats
    SAFE_DIVIDE(STDDEV(IF(v.itemid = vi.rr_itemid, v.valuenum, NULL)), AVG(IF(v.itemid = vi.rr_itemid, v.valuenum, NULL))) AS cv_rr,
    COUNTIF(v.itemid = vi.rr_itemid) AS n_rr,
    COUNTIF(v.itemid = vi.rr_itemid AND (v.valuenum < 8 OR v.valuenum > 30)) > 0 AS abnormal_rr
  FROM hhs_stays s
  LEFT JOIN vitals_24h v
    ON s.stay_id = v.stay_id
  CROSS JOIN vital_itemids vi
  GROUP BY s.stay_id
),
-- 5. Filter for stays with at least 2 measurements per vital
filtered_stats AS (
  SELECT
    s.stay_id,
    s.cv_hr, s.cv_map, s.cv_rr,
    (s.cv_hr + s.cv_map + s.cv_rr) AS instability_score,
    (CAST(s.abnormal_hr AS INT64) + CAST(s.abnormal_map AS INT64) + CAST(s.abnormal_rr AS INT64)) AS abnormal_vital_count
  FROM vital_stats s
  WHERE s.n_hr >= 2 AND s.n_map >= 2 AND s.n_rr >= 2
),
-- 6. Get LOS and mortality
stay_info AS (
  SELECT
    fs.stay_id,
    fs.instability_score,
    fs.abnormal_vital_count,
    hs.los AS icu_los,
    adm.hospital_expire_flag
  FROM filtered_stats fs
  JOIN hhs_stays hs
    ON fs.stay_id = hs.stay_id
  JOIN physionet-data.mimiciv_3_1_hosp.admissions adm
    ON hs.hadm_id = adm.hadm_id
),
-- 7. Assign decile and quartile
ranked_stays AS (
  SELECT
    *,
    NTILE(10) OVER (ORDER BY instability_score DESC) AS decile,
    NTILE(4) OVER (ORDER BY instability_score DESC) AS quartile
  FROM stay_info
)
-- 8. Final output: top quartile only
SELECT
  stay_id,
  instability_score,
  decile,
  abnormal_vital_count,
  icu_los,
  hospital_expire_flag
FROM ranked_stays
WHERE quartile = 1
ORDER BY instability_score DESC;