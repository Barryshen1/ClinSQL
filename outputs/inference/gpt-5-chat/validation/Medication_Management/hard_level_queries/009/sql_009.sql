WITH aki_cohort AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, pat.anchor_age, pat.gender,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.subject_id = dx.subject_id
    AND adm.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddx
    ON dx.icd_code = ddx.icd_code AND dx.icd_version = ddx.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 84 AND 94
    AND (
      ddx.long_title LIKE '%acute kidney%' 
      OR dx.icd_code LIKE '584%'  -- ICD-9 AKI
      OR dx.icd_code LIKE 'N17%'  -- ICD-10 AKI
    )
),
complexity AS (
  SELECT hadm_id, COUNT(DISTINCT LOWER(drug)) AS med_complexity
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  GROUP BY hadm_id
),
aki_with_complexity AS (
  SELECT a.*, c.med_complexity,
         NTILE(5) OVER (ORDER BY c.med_complexity) AS complexity_quintile
  FROM aki_cohort a
  LEFT JOIN complexity c
    ON a.hadm_id = c.hadm_id
),
readmissions AS (
  SELECT curr.hadm_id,
         CASE WHEN MIN(TIMESTAMP_DIFF(next.admittime, curr.dischtime, DAY)) <= 30
              THEN 1 ELSE 0 END AS readmit_30d
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` curr
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` next
    ON curr.subject_id = next.subject_id
   AND next.admittime > curr.dischtime
   AND TIMESTAMP_DIFF(next.admittime, curr.dischtime, DAY) <= 30
  GROUP BY curr.hadm_id
),
coa AS (
  -- Find overlapping anticoagulant and opioid drugs within same admission
  SELECT DISTINCT p1.hadm_id,
    COUNT(*) AS coadmin_count
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p1
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p2
    ON p1.hadm_id = p2.hadm_id
   AND p1.starttime IS NOT NULL AND p2.starttime IS NOT NULL
   AND p1.stoptime IS NOT NULL AND p2.stoptime IS NOT NULL
   AND p1.starttime < p2.stoptime
   AND p2.starttime < p1.stoptime
   AND REGEXP_CONTAINS(LOWER(p1.drug), '(warfarin|heparin|enoxaparin|dabigatran|rivaroxaban|apixaban)')
   AND REGEXP_CONTAINS(LOWER(p2.drug), '(morphine|oxycodone|hydromorphone|fentanyl|codeine|methadone|tramadol)')
  GROUP BY p1.hadm_id
),
final AS (
  SELECT awc.complexity_quintile,
         COUNT(*) AS admissions,
         AVG(awc.los_days) AS avg_los_days,
         100 * SUM(CASE WHEN awc.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_pct,
         100 * SUM(r.readmit_30d) / COUNT(*) AS readmit_30d_pct,
         COALESCE(SUM(co.coadmin_count),0) AS coadmin_events
  FROM aki_with_complexity awc
  LEFT JOIN readmissions r  ON awc.hadm_id = r.hadm_id
  LEFT JOIN coa co          ON awc.hadm_id = co.hadm_id
  GROUP BY awc.complexity_quintile
)
SELECT * FROM final
ORDER BY complexity_quintile;