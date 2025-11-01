WITH troponin_t_items AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),
acs_admissions AS (
  SELECT a.subject_id,
         a.hadm_id,
         a.admittime,
         a.dischtime,
         a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 9 AND (di.icd_code LIKE '410%' OR di.icd_code LIKE '411%' OR di.icd_code LIKE '412%' OR di.icd_code LIKE '413%' OR di.icd_code LIKE '414%'))
          OR (di.icd_version = 10 AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%' OR di.icd_code LIKE 'I24%' OR di.icd_code LIKE 'I25%'))
        )
    )
),
cohort_with_elevated_trop AS (
  SELECT aca.subject_id,
         aca.hadm_id,
         aca.admittime,
         aca.dischtime,
         aca.hospital_expire_flag
  FROM acs_admissions aca
  JOIN (
    SELECT subject_id, hadm_id, MIN(charttime) AS first_charttime
    FROM `physionet-data.mimiciv_3_1_hosp.labevents`
    WHERE itemid IN (SELECT itemid FROM troponin_t_items)
    GROUP BY subject_id, hadm_id
  ) t
    ON t.subject_id = aca.subject_id
   AND t.hadm_id = aca.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lv
    ON lv.subject_id = t.subject_id
   AND lv.hadm_id = t.hadm_id
   AND lv.charttime = t.first_charttime
  WHERE lv.valuenum IS NOT NULL
    AND lv.ref_range_upper IS NOT NULL
    AND lv.valuenum > lv.ref_range_upper
)
SELECT
  COUNT(*) AS cohort_size,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0) AS avg_los_days,
  AVG(CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) AS in_hospital_mortality_rate
FROM cohort_with_elevated_trop;