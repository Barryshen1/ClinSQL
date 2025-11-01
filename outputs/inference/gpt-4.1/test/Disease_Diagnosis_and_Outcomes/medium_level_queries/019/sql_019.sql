WITH hf_admissions AS (
  -- Heart failure admissions for males 53-63
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    adm.discharge_location,
    pat.anchor_age,
    pat.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      ON adm.hadm_id = dx.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddx
      ON dx.icd_code = ddx.icd_code AND dx.icd_version = ddx.icd_version
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 53 AND 63
    AND (
      -- ICD-10 I50.x or ICD-9 428.x, or any code with 'heart failure' in long_title
      ddx.long_title LIKE '%heart failure%'
      OR dx.icd_code LIKE 'I50%'
      OR dx.icd_code LIKE '428%'
    )
),

charlson_map AS (
  -- Map ICD codes to Charlson comorbidity categories
  -- See https://github.com/MIT-LCP/mimic-code/blob/main/concepts/comorbidity/charlson.sql
  SELECT
    hadm_id,
    MAX(
      CASE
        WHEN (icd_version = 9 AND icd_code BETWEEN '41000' AND '41499') OR
             (icd_version = 10 AND icd_code BETWEEN 'I21' AND 'I25') THEN 1 ELSE 0
      END
    ) AS MI,
    MAX(
      CASE
        WHEN (icd_version = 9 AND icd_code BETWEEN '42800' AND '42899') OR
             (icd_version = 10 AND icd_code LIKE 'I50%') THEN 1 ELSE 0
      END
    ) AS CHF,
    MAX(
      CASE
        WHEN (icd_version = 9 AND icd_code BETWEEN '42600' AND '42799') OR
             (icd_version = 10 AND icd_code BETWEEN 'I44' AND 'I49') THEN 1 ELSE 0
      END
    ) AS PVD,
    MAX(
      CASE
        WHEN (icd_version = 9 AND icd_code BETWEEN '43000' AND '43899') OR
             (icd_version = 10 AND icd_code BETWEEN 'I60' AND 'I69') THEN 1 ELSE 0
      END
    ) AS CVD,
    MAX(
      CASE
        WHEN (icd_version = 9 AND icd_code BETWEEN '25000' AND '25099') OR
             (icd_version = 10 AND icd_code LIKE 'E10%' OR icd_code LIKE 'E11%') THEN 1 ELSE 0
      END
    ) AS DM,
    MAX(
      CASE
        WHEN (icd_version = 9 AND icd_code BETWEEN '58500' AND '58599') OR
             (icd_version = 10 AND icd_code LIKE 'N18%') THEN 1 ELSE 0
      END
    ) AS RENAL,
    MAX(
      CASE
        WHEN (icd_version = 9 AND icd_code BETWEEN '57100' AND '57199') OR
             (icd_version = 10 AND icd_code LIKE 'K70%' OR icd_code LIKE 'K74%') THEN 1 ELSE 0
      END
    ) AS LIVER,
    MAX(
      CASE
        WHEN (icd_version = 9 AND icd_code BETWEEN '14000' AND '19999') OR
             (icd_version = 10 AND icd_code LIKE 'C%' AND icd_code NOT LIKE 'C44%') THEN 1 ELSE 0
      END
    ) AS MALIGNANCY,
    MAX(
      CASE
        WHEN (icd_version = 9 AND icd_code BETWEEN '20000' AND '20899') OR
             (icd_version = 10 AND icd_code LIKE 'C81%' OR icd_code LIKE 'C96%') THEN 1 ELSE 0
      END
    ) AS LYMPHOMA,
    MAX(
      CASE
        WHEN (icd_version = 9 AND icd_code BETWEEN '04200' AND '04499') OR
             (icd_version = 10 AND icd_code LIKE 'B20%') THEN 1 ELSE 0
      END
    ) AS AIDS
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY
    hadm_id
),

charlson_score AS (
  -- Calculate Charlson index per admission
  SELECT
    hadm_id,
    -- Weights per comorbidity (simplified, see Charlson index for full weights)
    1 * MI +
    1 * CHF +
    1 * PVD +
    1 * CVD +
    1 * DM +
    2 * RENAL +
    2 * LIVER +
    2 * MALIGNANCY +
    2 * LYMPHOMA +
    6 * AIDS AS charlson_index
  FROM
    charlson_map
),

main AS (
  SELECT
    hfa.subject_id,
    hfa.hadm_id,
    hfa.admittime,
    hfa.dischtime,
    hfa.hospital_expire_flag,
    hfa.discharge_location,
    hfa.anchor_age,
    charlson_score.charlson_index,
    -- LOS in days
    SAFE_CAST(TIMESTAMP_DIFF(hfa.dischtime, hfa.admittime, DAY) AS INT64) AS los_days
  FROM
    hf_admissions hfa
    LEFT JOIN charlson_score
      ON hfa.hadm_id = charlson_score.hadm_id
  WHERE
    hfa.admittime IS NOT NULL
    AND hfa.dischtime IS NOT NULL
    AND charlson_score.charlson_index IS NOT NULL
)

, categorized AS (
  SELECT
    *,
    -- LOS category
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
      WHEN los_days >= 8 THEN '>=8'
      ELSE NULL
    END AS los_cat,
    -- Charlson category
    CASE
      WHEN charlson_index <= 3 THEN '<=3'
      WHEN charlson_index BETWEEN 4 AND 5 THEN '4-5'
      WHEN charlson_index > 5 THEN '>5'
      ELSE NULL
    END AS charlson_cat,
    -- Discharge destination mapping
    CASE
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
      WHEN LOWER(discharge_location) LIKE '%rehab%' THEN 'Rehab'
      WHEN LOWER(discharge_location) LIKE '%skilled%' OR LOWER(discharge_location) LIKE '%snf%' THEN 'SNF'
      WHEN LOWER(discharge_location) LIKE '%hospice%' THEN 'Hospice'
      ELSE 'Other'
    END AS discharge_dest
  FROM
    main
  WHERE
    los_days IS NOT NULL
    AND charlson_index IS NOT NULL
)

, summary AS (
  SELECT
    los_cat,
    charlson_cat,
    COUNT(*) AS n_admissions,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS n_deaths,
    100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_pct,
    AVG(los_days) AS mean_los,
    -- Discharge destination percentages
    100.0 * SUM(CASE WHEN discharge_dest = 'Home' THEN 1 ELSE 0 END) / COUNT(*) AS pct_home,
    100.0 * SUM(CASE WHEN discharge_dest = 'Rehab' THEN 1 ELSE 0 END) / COUNT(*) AS pct_rehab,
    100.0 * SUM(CASE WHEN discharge_dest = 'SNF' THEN 1 ELSE 0 END) / COUNT(*) AS pct_snf,
    100.0 * SUM(CASE WHEN discharge_dest = 'Hospice' THEN 1 ELSE 0 END) / COUNT(*) AS pct_hospice,
    100.0 * SUM(CASE WHEN discharge_dest = 'Other' THEN 1 ELSE 0 END) / COUNT(*) AS pct_other
  FROM
    categorized
  WHERE
    los_cat IS NOT NULL
    AND charlson_cat IS NOT NULL
  GROUP BY
    los_cat, charlson_cat
)

, los_stats AS (
  -- For absolute and relative LOS differences by Charlson group (reference: charlson_cat='<=3')
  SELECT
    los_cat,
    charlson_cat,
    mean_los,
    -- Get reference mean_los for charlson_cat='<=3' in same los_cat
    FIRST_VALUE(mean_los) OVER (PARTITION BY los_cat ORDER BY charlson_cat) AS ref_mean_los,
    mean_los - FIRST_VALUE(mean_los) OVER (PARTITION BY los_cat ORDER BY charlson_cat) AS abs_los_diff,
    CASE
      WHEN FIRST_VALUE(mean_los) OVER (PARTITION BY los_cat ORDER BY charlson_cat) > 0
      THEN mean_los / FIRST_VALUE(mean_los) OVER (PARTITION BY los_cat ORDER BY charlson_cat)
      ELSE NULL
    END AS rel_los_diff,
    n_admissions,
    n_deaths,
    mortality_pct,
    pct_home,
    pct_rehab,
    pct_snf,
    pct_hospice,
    pct_other
  FROM
    summary
)

SELECT
  los_cat,
  charlson_cat,
  n_admissions,
  mortality_pct,
  mean_los,
  abs_los_diff,
  rel_los_diff,
  pct_home,
  pct_rehab,
  pct_snf,
  pct_hospice,
  pct_other
FROM
  los_stats
ORDER BY
  los_cat, charlson_cat;