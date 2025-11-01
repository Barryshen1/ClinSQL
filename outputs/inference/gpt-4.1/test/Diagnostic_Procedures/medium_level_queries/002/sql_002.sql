WITH tia_admissions AS (
  -- Step 1: Find admissions with TIA diagnosis
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE (
    -- ICD-9: 435.x
    (d.icd_version = 9 AND dd.icd_code LIKE '435%')
    -- ICD-10: G45.x
    OR (d.icd_version = 10 AND dd.icd_code LIKE 'G45%')
  )
),
filtered_admissions AS (
  -- Step 2 & 3: Join with patients and admissions, filter by age, gender, LOS
  SELECT
    ta.subject_id,
    ta.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM tia_admissions ta
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON ta.subject_id = p.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON ta.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
icu_flag AS (
  -- Step 4: ICU use flag
  SELECT DISTINCT hadm_id, TRUE AS icu_use
  FROM physionet-data.mimiciv_3_1_icu.icustays
),
ultrasound_counts AS (
  -- Step 5: Count ultrasound/echo procedures per admission
  SELECT
    fa.subject_id,
    fa.hadm_id,
    COUNT(*) AS num_ultrasound_echo
  FROM filtered_admissions fa
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.procedures_icd pi
    ON fa.subject_id = pi.subject_id AND fa.hadm_id = pi.hadm_id
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.d_icd_procedures dpi
    ON pi.icd_code = dpi.icd_code AND pi.icd_version = dpi.icd_version
  WHERE dpi.long_title IS NOT NULL
    AND (
      LOWER(dpi.long_title) LIKE '%ultrasound%'
      OR LOWER(dpi.long_title) LIKE '%echocardiogram%'
    )
  GROUP BY fa.subject_id, fa.hadm_id
),
final AS (
  -- Step 6: Merge all info, fill zero for admissions with no procedures
  SELECT
    fa.subject_id,
    fa.hadm_id,
    fa.los,
    CASE
      WHEN fa.los BETWEEN 1 AND 3 THEN '1-3'
      WHEN fa.los BETWEEN 4 AND 7 THEN '4-7'
    END AS los_group,
    IFNULL(uc.num_ultrasound_echo, 0) AS num_ultrasound_echo,
    IFNULL(icuf.icu_use, FALSE) AS icu_use
  FROM filtered_admissions fa
  LEFT JOIN ultrasound_counts uc
    ON fa.subject_id = uc.subject_id AND fa.hadm_id = uc.hadm_id
  LEFT JOIN icu_flag icuf
    ON fa.hadm_id = icuf.hadm_id
)
-- Step 7: Aggregate mean per group
SELECT
  los_group,
  icu_use,
  COUNT(*) AS num_admissions,
  AVG(num_ultrasound_echo) AS mean_ultrasound_echo_per_admission
FROM final
WHERE los_group IS NOT NULL
GROUP BY los_group, icu_use
ORDER BY los_group, icu_use DESC;