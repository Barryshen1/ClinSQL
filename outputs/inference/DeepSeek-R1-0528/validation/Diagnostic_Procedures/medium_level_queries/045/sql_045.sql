WITH base_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_adm,
    p.gender,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 78 AND 88
    AND adm.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        (icd_version = 9 AND icd_code LIKE '4534%') 
        OR (icd_version = 10 AND icd_code LIKE 'I82%')
    )
),
filtered_admissions AS (
  SELECT *
  FROM base_admissions
  WHERE los_days BETWEEN 1 AND 8
),
admissions_with_icu AS (
  SELECT 
    *,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_icu.icustays` icu 
        WHERE icu.hadm_id = fa.hadm_id
      ) THEN 1 
      ELSE 0 
    END AS had_icu
  FROM filtered_admissions fa
),
admission_diagnostics AS (
  SELECT 
    a.hadm_id,
    a.los_days,
    a.had_icu,
    (
      SELECT COUNT(*) 
      FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
        ON le.itemid = dli.itemid
      WHERE 
        le.hadm_id = a.hadm_id
        AND le.charttime BETWEEN a.admittime AND a.dischtime
        AND dli.label LIKE '%D-dimer%'
    ) 
    +
    (
      SELECT COUNT(*) 
      FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hc
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh
        ON hc.hcpcs_cd = dh.code
      WHERE 
        hc.hadm_id = a.hadm_id
        AND (
          dh.code IN ('93970', '93971', '93978', '93979') 
          OR (dh.short_description LIKE '%duplex%' 
              AND (dh.short_description LIKE '%vein%' OR dh.short_description LIKE '%venous%'))
        )
        AND hc.chartdate BETWEEN DATE(a.admittime) AND DATE(a.dischtime)
    ) AS total_diagnostics
  FROM admissions_with_icu a
)
SELECT 
  CASE WHEN had_icu = 1 THEN 'ICU' ELSE 'No ICU' END AS icu_stratum,
  CASE 
    WHEN los_days BETWEEN 1 AND 4 THEN '1-4'
    WHEN los_days BETWEEN 5 AND 8 THEN '5-8'
  END AS los_group,
  COUNT(hadm_id) AS num_admissions,
  AVG(total_diagnostics) AS mean_diagnostics_per_admission
FROM admission_diagnostics
GROUP BY icu_stratum, los_group
ORDER BY icu_stratum, los_group;