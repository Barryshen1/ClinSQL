WITH acs_admissions AS (
  -- Identify ACS admissions in females age 46-56
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    pat.anchor_age,
    pat.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      ON adm.hadm_id = dx.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dxdef
      ON dx.icd_code = dxdef.icd_code AND dx.icd_version = dxdef.icd_version
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 46 AND 56
    AND (
      -- ACS ICD-10 codes: I21 (STEMI/NSTEMI), I20.0 (unstable angina), I22 (subsequent MI)
      (dx.icd_version = 10 AND (
        dx.icd_code LIKE 'I21%' OR
        dx.icd_code LIKE 'I22%' OR
        dx.icd_code = 'I200'
      ))
      -- ACS ICD-9 codes: 410 (MI), 411.1 (unstable angina)
      OR (dx.icd_version = 9 AND (
        dx.icd_code LIKE '410%' OR
        dx.icd_code = '4111'
      ))
    )
),
hs_tnt_items AS (
  -- Find hs-TnT itemids
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    LOWER(label) LIKE '%troponin%' AND
    (LOWER(label) LIKE '%t%' OR LOWER(label) LIKE '%hs%' OR LOWER(label) LIKE '%high%')
),
first_hs_tnt AS (
  -- Get first hs-TnT result per ACS admission
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum,
    le.valueuom,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime ASC, le.labevent_id ASC) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN hs_tnt_items hsi ON le.itemid = hsi.itemid
  WHERE
    le.valuenum IS NOT NULL
)
,
acs_with_hs_tnt AS (
  -- Join ACS admissions to first hs-TnT result
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.anchor_age,
    a.gender,
    fht.charttime AS hs_tnt_time,
    fht.valuenum AS hs_tnt_value,
    fht.valueuom
  FROM
    acs_admissions a
    JOIN first_hs_tnt fht
      ON a.subject_id = fht.subject_id AND a.hadm_id = fht.hadm_id
  WHERE
    fht.rn = 1
)
,
categorized AS (
  -- Categorize hs-TnT result
  SELECT
    *,
    CASE
      WHEN hs_tnt_value < 14 THEN 'Normal'
      WHEN hs_tnt_value >= 14 AND hs_tnt_value <= 52 THEN 'Borderline'
      WHEN hs_tnt_value > 52 THEN 'Myocardial Injury'
      ELSE 'Unknown'
    END AS hs_tnt_category,
    SAFE_DIVIDE(TIMESTAMP_DIFF(dischtime, admittime, SECOND), 86400) AS los_days
  FROM
    acs_with_hs_tnt
  WHERE
    -- Only include results in ng/L or blank (MIMIC hs-TnT is usually ng/L)
    (LOWER(valueuom) = 'ng/l' OR valueuom IS NULL OR valueuom = '')
)
,
agg AS (
  -- Aggregate counts, percentages, mean LOS
  SELECT
    hs_tnt_category,
    COUNT(*) AS admission_count,
    SAFE_DIVIDE(COUNT(*), SUM(COUNT(*)) OVER ()) * 100 AS percent_of_total,
    AVG(los_days) AS mean_los_days
  FROM
    categorized
  WHERE
    hs_tnt_category IN ('Normal', 'Borderline', 'Myocardial Injury')
  GROUP BY
    hs_tnt_category
)
SELECT
  hs_tnt_category,
  admission_count,
  ROUND(percent_of_total, 1) AS percent_of_total,
  ROUND(mean_los_days, 2) AS mean_los_days
FROM
  agg
ORDER BY
  hs_tnt_category
;