WITH
  -- Base: female patients aged 45-55 at admission
  patient_filtered AS (
    SELECT
      p.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON p.subject_id = a.subject_id
    WHERE p.gender = 'F'
      AND p.anchor_age BETWEEN 45 AND 55
  ),

  -- HF flags per admission: primary (seq_num = 1) or secondary (seq_num > 1)
  hf_flags AS (
    SELECT
      pf.hadm_id,
      MAX(CASE
            WHEN di.seq_num = 1
                 AND (COALESCE(dd.long_title, '') LIKE '%heart failure%' OR
                      COALESCE(dd.long_title, '') LIKE '%congestive heart failure%')
            THEN 1 ELSE 0
          END) AS has_primary_hf,
      MAX(CASE
            WHEN di.seq_num > 1
                 AND (COALESCE(dd.long_title, '') LIKE '%heart failure%' OR
                      COALESCE(dd.long_title, '') LIKE '%congestive heart failure%')
            THEN 1 ELSE 0
          END) AS has_secondary_hf
    FROM patient_filtered pf
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      ON di.subject_id = pf.subject_id AND di.hadm_id = pf.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    GROUP BY pf.hadm_id
  ),

  -- Imaging counts from ICU chartevents (CT/MRI items)
  imaging_ct AS (
    SELECT hadm_id, COUNT(*) AS ctv
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON di.itemid = ce.itemid
    WHERE LOWER(di.label) LIKE '%ct%' OR LOWER(di.label) LIKE '%mri%'
    GROUP BY hadm_id
  ),
  -- Imaging counts from ICU procedureevents (CT/MRI items)
  imaging_proc AS (
    SELECT hadm_id, COUNT(*) AS pv
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON di.itemid = pe.itemid
    WHERE LOWER(di.label) LIKE '%ct%' OR LOWER(di.label) LIKE '%mri%'
    GROUP BY hadm_id
  ),
  -- Total CT/MRI imaging counts per admission (combine both sources)
  imaging_tot AS (
    SELECT COALESCE(ct.hadm_id, pr.hadm_id) AS hadm_id,
           COALESCE(ct.ctv, 0) + COALESCE(pr.pv, 0) AS imaging_cnt
    FROM imaging_ct ct
    FULL OUTER JOIN imaging_proc pr
      ON ct.hadm_id = pr.hadm_id
  )

-- Part B: aggregate by HF primary/secondary and LOS bins
SELECT
  hf_class,
  los_bin,
  AVG(imaging_cnt) AS mean_ct_mri_per_admission,
  MIN(imaging_cnt) AS min_ct_mri_per_admission,
  MAX(imaging_cnt) AS max_ct_mri_per_admission
FROM (
  SELECT
    pf.hadm_id,
    CASE
      WHEN f.has_primary_hf = 1 THEN 'Primary'
      WHEN f.has_secondary_hf = 1 THEN 'Secondary'
      ELSE 'Other'
    END AS hf_class,
    CASE
      WHEN pf.los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN pf.los_days BETWEEN 4 AND 7 THEN '4-7'
    END AS los_bin,
    COALESCE(it.imaging_cnt, 0) AS imaging_cnt
  FROM patient_filtered pf
  LEFT JOIN hf_flags f ON f.hadm_id = pf.hadm_id
  LEFT JOIN imaging_tot it ON it.hadm_id = pf.hadm_id
  WHERE pf.los_days BETWEEN 1 AND 7
    AND (f.has_primary_hf = 1 OR f.has_secondary_hf = 1)
) t
GROUP BY hf_class, los_bin
ORDER BY hf_class, los_bin;