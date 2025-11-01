WITH cohort AS (
  -- Base cohort: males 43-53 with hepatic failure admission
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND a.admission_type IN ('EMERGENCY', 'ELECTIVE', 'URGENT')
    AND d.icd_version = '10'
    AND (d.icd_code LIKE 'K7%' OR d.icd_code LIKE 'K74%')
    AND a.admittime IS NOT NULL
),

window_times AS (
  -- Add 72-hour window per admission
  SELECT *,
    TIMESTAMP_ADD(admittime, INTERVAL 72 HOUR) AS window_end
  FROM cohort
),

mcs_prescriptions AS (
  -- Medication complexity from prescriptions (hospital-wide)
  SELECT 
    w.subject_id,
    w.hadm_id,
    SUM(
      COUNT(DISTINCT normalized_drug) * 
      COALESCE(SAFE_CAST(pr.doses_per_24_hrs AS FLOAT64), 1.0)
    ) AS mcs_pres
  FROM window_times w
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON w.subject_id = pr.subject_id 
    AND w.hadm_id = pr.hadm_id
    AND pr.starttime >= w.admittime
    AND pr.starttime <= w.window_end
    AND pr.drug IS NOT NULL
    AND LOWER(REGEXP_REPLACE(pr.drug, r' \d+ (mg|mcg|ml|tab|caps?|gm).*', '')) <> ''
  CROSS JOIN UNNEST(ARRAY(SELECT LOWER(REGEXP_REPLACE(pr.drug, r' \d+ (mg|mcg|ml|tab|caps?|gm).*', '')))) AS normalized_drug
  GROUP BY w.subject_id, w.hadm_id
),

mcs_icu AS (
  -- Medication complexity from ICU inputevents (if applicable)
  SELECT 
    w.subject_id,
    w.hadm_id,
    SUM(
      COUNT(DISTINCT normalized_label) * 
      COALESCE(ie.rate / 24.0, 4.0)  -- Proxy: rate/24 for infusions, else q6h=4
    ) AS mcs_icu
  FROM window_times w
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON w.subject_id = icu.subject_id 
    AND w.hadm_id = icu.hadm_id
    AND icu.intime <= w.window_end 
    AND (icu.outtime >= w.admittime OR icu.outtime IS NULL)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON icu.subject_id = ie.subject_id 
    AND icu.stay_id = ie.stay_id
    AND ie.starttime >= w.admittime
    AND ie.starttime <= w.window_end
    AND ie.itemid IN (
      SELECT itemid 
      FROM `physionet-data.mimiciv_3_1_icu.d_items` 
      WHERE category LIKE '%Medication%' OR label LIKE '%Infusion%' OR category LIKE '%Drug%'
    )
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ie.itemid = di.itemid AND di.label IS NOT NULL
  CROSS JOIN UNNEST(ARRAY(SELECT LOWER(REGEXP_REPLACE(COALESCE(di.label, ''), r' \d+ (mg|mcg|ml|tab|caps?|gm).*', '')))) AS normalized_label
  WHERE di.label IS NOT NULL OR icu.stay_id IS NULL  -- Include non-ICU
  GROUP BY w.subject_id, w.hadm_id
),

base_mcs AS (
  -- Combine MCS sources
  SELECT 
    w.*,
    COALESCE(mp.mcs_pres, 0) + COALESCE(mi.mcs_icu, 0) AS mcs_score
  FROM window_times w
  LEFT JOIN mcs_prescriptions mp
    ON w.subject_id = mp.subject_id AND w.hadm_id = mp.hadm_id
  LEFT JOIN mcs_icu mi
    ON w.subject_id = mi.subject_id AND w.hadm_id = mi.hadm_id
),

readmissions AS (
  -- 30-day readmission calculation (per patient, using all admissions)
  SELECT 
    b.subject_id,
    b.hadm_id,
    CASE WHEN COUNT(DISTINCT ra.hadm_id) > 0 THEN 1 ELSE 0 END AS has_readmission
  FROM base_mcs b
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` ra
    ON b.subject_id = ra.subject_id
    AND ra.admittime > b.dischtime
    AND ra.admittime <= TIMESTAMP_ADD(b.dischtime, INTERVAL 30 DAY)
    AND ra.admission_type IN ('EMERGENCY', 'ELECTIVE', 'URGENT')
    AND ra.hadm_id != b.hadm_id  -- Exclude self
  WHERE b.dischtime IS NOT NULL
  GROUP BY b.subject_id, b.hadm_id
),

quintiles AS (
  -- Add quintiles
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY mcs_score) AS quintile
  FROM base_mcs
)

-- Final aggregation per quintile
SELECT 
  quintile,
  COUNT(*) AS n,
  MIN(mcs_score) AS min_score,
  MAX(mcs_score) AS max_score,
  AVG(mcs_score) AS mean_score,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_los_days,
  SAFE_DIVIDE(
    SUM(CAST(hospital_expire_flag AS INT64)), 
    COUNT(*)
  ) * 100 AS in_hospital_mortality_pct,
  SAFE_DIVIDE(
    SUM(CAST(COALESCE(r.has_readmission, 0) AS INT64)), 
    COUNT(DISTINCT q.subject_id)
  ) * 100 AS readmission_30d_pct
FROM quintiles q
LEFT JOIN readmissions r
  ON q.subject_id = r.subject_id AND q.hadm_id = r.hadm_id
GROUP BY quintile
ORDER BY quintile;