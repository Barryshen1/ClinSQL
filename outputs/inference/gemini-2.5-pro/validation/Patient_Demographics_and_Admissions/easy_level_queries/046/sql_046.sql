WITH
  -- Step 1: Identify male patients aged 37-47
  patient_cohort AS (
    SELECT
      subject_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE
      gender = 'M'
      AND anchor_age BETWEEN 37 AND 47
  ),

  -- Step 2: Isolate the first hospital admission for this cohort
  first_admissions AS (
    SELECT
      adm.subject_id,
      adm.hadm_id,
      adm.hospital_expire_flag
    FROM (
      SELECT
        subject_id,
        hadm_id,
        hospital_expire_flag,
        ROW_NUMBER() OVER (
          PARTITION BY
            subject_id
          ORDER BY
            admittime ASC
        ) AS rn
      FROM
        `physionet-data.mimiciv_3_1_hosp.admissions`
      WHERE
        subject_id IN (
          SELECT
            subject_id
          FROM
            patient_cohort
        )
    ) AS adm
    WHERE
      adm.rn = 1
  ),

  -- Step 3: Identify admissions where DAPT was prescribed
  -- DAPT = Aspirin + a P2Y12 Inhibitor (Clopidogrel, Prasugrel, Ticagrelor)
  dapt_admissions AS (
    SELECT
      hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE
      -- Filter to only prescriptions for the admissions we care about
      hadm_id IN (
        SELECT
          hadm_id
        FROM
          first_admissions
      )
      -- Use a CASE statement to classify the antiplatelet drug type
      AND (
        CASE
          WHEN LOWER(drug) LIKE '%aspirin%'
          THEN 'aspirin'
          WHEN
            LOWER(drug) LIKE '%clopidogrel%'
            OR LOWER(drug) LIKE '%prasugrel%'
            OR LOWER(drug) LIKE '%ticagrelor%'
          THEN 'p2y12_inhibitor'
          ELSE NULL
        END
      ) IS NOT NULL
    GROUP BY
      hadm_id
    -- Ensure both drug classes were prescribed for the admission
    HAVING
      COUNT(
        DISTINCT (
          CASE
            WHEN LOWER(drug) LIKE '%aspirin%'
            THEN 'aspirin'
            WHEN
              LOWER(drug) LIKE '%clopidogrel%'
              OR LOWER(drug) LIKE '%prasugrel%'
              OR LOWER(drug) LIKE '%ticagrelor%'
            THEN 'p2y12_inhibitor'
          END
        )
      ) = 2
  )

-- Step 4: Calculate the standard deviation of mortality for the final cohort
SELECT
  STDDEV_SAMP(fa.hospital_expire_flag) AS sd_in_hospital_mortality
FROM
  first_admissions AS fa
-- Join to filter for only those admissions that received DAPT
INNER JOIN
  dapt_admissions AS da
  ON fa.hadm_id = da.hadm_id;