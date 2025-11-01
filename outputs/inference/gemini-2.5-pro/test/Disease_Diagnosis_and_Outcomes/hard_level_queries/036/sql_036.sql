WITH
  -- Step 1: Identify all hospital admissions with a pneumonia diagnosis
  Pneumonia_Admissions AS (
    SELECT DISTINCT
      dx.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
      ON dx.icd_code = d.icd_code AND dx.icd_version = d.icd_version
    WHERE
      LOWER(d.long_title) LIKE '%pneumonia%'
  ),
  -- Step 2: Calculate Charlson Comorbidity Index (CCI) for all admissions
  -- This creates flags for each condition to avoid double counting within one admission
  CharlsonComponents AS (
    SELECT
      hadm_id,
      MAX(
        CASE
          WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('410', '412')) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I21', 'I22')) THEN 1
          ELSE 0
        END
      ) AS mi,
      MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '428') OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'I50') THEN 1 ELSE 0 END) AS chf,
      MAX(
        CASE
          WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('440', '441', '443')) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I70', 'I71', 'I73')) THEN 1
          ELSE 0
        END
      ) AS pvd,
      MAX(
        CASE
          WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) BETWEEN '430' AND '438') OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) BETWEEN 'I60' AND 'I69') THEN 1
          ELSE 0
        END
      ) AS cevd,
      MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '290') OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('G30', 'F01', 'F02', 'F03')) THEN 1 ELSE 0 END) AS dementia,
      MAX(
        CASE
          WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) BETWEEN '490' AND '508') OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) BETWEEN 'J40' AND 'J47') THEN 1
          ELSE 0
        END
      ) AS cpd,
      MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '714') OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'M05') THEN 1 ELSE 0 END) AS rheumd,
      MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '531') OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'K25') THEN 1 ELSE 0 END) AS pud,
      MAX(
        CASE
          WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '571') OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'K70') THEN 1 -- Mild Liver
          WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 4) = '5722') OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'K72') THEN 3 -- Mod/Sev Liver
          ELSE 0
        END
      ) AS liver,
      MAX(
        CASE
          WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 4) BETWEEN '2500' AND '2503') OR (icd_version = 10 AND SUBSTR(icd_code, 1, 4) IN ('E100', 'E101', 'E109', 'E110', 'E111', 'E119')) THEN 1 -- No complication
          WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 4) BETWEEN '2504' AND '2509') OR (icd_version = 10 AND SUBSTR(icd_code, 1, 4) IN ('E102', 'E112', 'E103', 'E113')) THEN 2 -- With complication
          ELSE 0
        END
      ) AS diabetes,
      MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '342') OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'G81') THEN 2 ELSE 0 END) AS hemi,
      MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '585') OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'N18') THEN 2 ELSE 0 END) AS renal,
      MAX(
        CASE
          WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) BETWEEN '140' AND '172') OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) BETWEEN 'C00' AND 'C76') THEN 2 -- Cancer
          WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('196', '197', '198')) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('C77', 'C78', 'C79')) THEN 6 -- Mets
          ELSE 0
        END
      ) AS cancer,
      MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '042') OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'B20') THEN 6 ELSE 0 END) AS aids
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY
      hadm_id
  ),
  CharlsonScore AS (
    SELECT
      hadm_id,
      (mi + chf + pvd + cevd + dementia + cpd + rheumd + pud + liver + diabetes + hemi + renal + cancer + aids) AS cci
    FROM
      CharlsonComponents
  ),
  -- Step 3: Define the base cohort of male patients aged 73-83 with pneumonia
  BaseCohort AS (
    SELECT
      p.subject_id,
      a.hadm_id,
      p.anchor_age
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    WHERE
      p.gender = 'M'
      AND p.anchor_age BETWEEN 73 AND 83
      AND a.hadm_id IN (
        SELECT hadm_id FROM Pneumonia_Admissions
      )
  ),
  -- Step 4: Add CCI score and determine the comorbidity quartile
  CohortWithCCI AS (
    SELECT
      bc.subject_id,
      bc.hadm_id,
      bc.anchor_age,
      COALESCE(cs.cci, 0) AS cci,
      NTILE(4) OVER (
        ORDER BY
          COALESCE(cs.cci, 0) DESC
      ) AS cci_quartile
    FROM
      BaseCohort AS bc
      LEFT JOIN CharlsonScore AS cs
      ON bc.hadm_id = cs.hadm_id
  ),
  -- Step 5: Filter for the final cohort (top quartile of comorbidity)
  FinalCohort AS (
    SELECT
      subject_id,
      hadm_id,
      anchor_age,
      cci
    FROM
      CohortWithCCI
    WHERE
      cci_quartile = 1
  ),
  -- Step 6: Identify admissions with major complications (Vent, Vaso, CRRT)
  MajorComplications AS (
    SELECT DISTINCT
      hadm_id
    FROM
      `physionet-data.mimiciv_3_1_icu.procedureevents`
    WHERE
      itemid IN (
        225792, -- Invasive Venitlation
        225802, -- CRRT
        225803, -- CRRT Dialysate
        225805 -- CRRT Adsorber
      )
    UNION DISTINCT
    SELECT DISTINCT
      hadm_id
    FROM
      `physionet-data.mimiciv_3_1_icu.inputevents`
    WHERE
      itemid IN (
        221906, -- Norepinephrine
        222315, -- Vasopressin
        221289, -- Epinephrine
        221662, -- Dopamine
        221749 -- Phenylephrine
      )
  ),
  -- Step 7: Combine cohort with outcomes and complication flags
  CohortWithOutcomes AS (
    SELECT
      fc.subject_id,
      fc.hadm_id,
      fc.anchor_age,
      adm.hospital_expire_flag,
      adm.admittime,
      adm.deathtime,
      CASE
        WHEN mc.hadm_id IS NOT NULL THEN 1
        ELSE 0
      END AS has_major_complication
    FROM
      FinalCohort AS fc
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON fc.hadm_id = adm.hadm_id
      LEFT JOIN MajorComplications AS mc
      ON fc.hadm_id = mc.hadm_id
  ),
  -- Step 8: Define composite risk level and calculate percentile rank
  RankedCohort AS (
    SELECT
      *,
      -- Define composite risk: 2 for death, 1 for complication, 0 for neither
      CASE
        WHEN hospital_expire_flag = 1 THEN 2
        WHEN has_major_complication = 1 THEN 1
        ELSE 0
      END AS composite_risk_level,
      -- Calculate percentile rank based on risk level
      PERCENT_RANK() OVER (
        ORDER BY
          (
            CASE
              WHEN hospital_expire_flag = 1 THEN 2
              WHEN has_major_complication = 1 THEN 1
              ELSE 0
            END
          )
      ) * 100 AS risk_percentile
    FROM
      CohortWithOutcomes
  )
-- Final Step: Calculate and present the required metrics
SELECT
  (
    SELECT
      AVG(risk_percentile)
    FROM
      RankedCohort
    WHERE
      anchor_age = 78
  ) AS patient_composite_risk_percentile,
  AVG(hospital_expire_flag) * 100 AS cohort_in_hospital_mortality_pct,
  AVG(has_major_complication) * 100 AS cohort_major_complication_pct,
  -- Calculate median survival days only for those who died
  APPROX_QUANTILES(
    IF(
      hospital_expire_flag = 1, DATETIME_DIFF(deathtime, admittime, DAY), NULL
    ),
    100
  ) [
  OFFSET
    (50)] AS median_survival_days_for_deceased
FROM
  RankedCohort;